dofile("table_show.lua")
dofile("urlcode.lua")
JSON = (loadfile "JSON.lua")()

local item_value = os.getenv('item_value')
local item_type = os.getenv('item_type')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local ids = {}
local item_value_escaped = string.gsub(item_value, "([^%w])", "%%%1")

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(url, "'+")
      or string.match(url, "[<>\\%*%$;%^%[%],%(%){}\n]")
      or string.match(url, "/!api/internal/")
      or string.match(url, "/api/1%.0/")
      or string.match(url, "/!api/1%.0/")
      or string.match(url, "/!?api/2%.0/repositories/[^/]+/[^/]+/hooks$")
      or string.match(url, "/!?api/2%.0/repositories/[^/]+/[^/]+/issues/[0-9]+/vote$")
      or string.match(url, "/!?api/2%.0/repositories/[^/]+/[^/]+/issues/[0-9]+/watch$")
      or string.match(url, "/!?api/2%.0/repositories/[^/]+/[^/]+/issues/[0-9]+/comments/[0-9]+$")
      or string.match(url, "/!?api/2%.0/repositories/[^/]+/[^/]+/pullrequests/[0-9]+/approve$")
      or string.match(url, "/!?api/2%.0/repositories/[^/]+/[^/]+/pullrequests/[0-9]+/merge$")
      or string.match(url, "/!?api/2%.0/repositories/[^/]+/[^/]+/pullrequests/[0-9]+/decline$")
      or string.match(url, "/!?api/2%.0/repositories/[^/]+/[^/]+/commit/[0-9a-f]+/approve$")
      or string.match(url, "/!?api/2%.0/repositories/[^/]+/[^/]+/filehistory/")
      or string.match(url, "/!?api/2%.0/repositories/[^/]+/[^/]+/src/")
      or string.match(url, "/!?api/2%.0/repositories/[^/]+/[^/]+/diff/")
      or string.match(url, "/!?api/2%.0/repositories/[^/]+/[^/]+/patch/")
      or string.match(url, "/!?api/2%.0/repositories/[^/]+/[^/]+/commit/")
      or string.match(url, "/!?api/2%.0/repositories/[^/]+/[^/]+/commits/[^%?]*%?.+page=[0-9]+$")
      or string.match(url, "/!?api/2%.0/repositories/[^/]+/[^/]+/commits%?.+page=[0-9]+$")
      or string.match(url, "/api/internal/repositories/[^/]+/[^/]+/src/")
      or string.match(url, "/api/internal/repositories/[^/]+/[^/]+/conflicts/")
      or string.match(url, "/[^/]+/[^/]+/commits/[0-9a-f]+%??[^/]*$")
      or string.match(url, "/[^/]+/[^/]+/wiki/commits/[0-9a-f]+$")
      or string.match(url, "/[^/]+/[^/]+/src/[0-9a-zA-Z]+")
      or string.match(url, "/[^/]+/[^/]+/branches/merge/")
      or string.match(url, "/[^/]+/[^/]+/compare/")
      or string.match(url, "/[^/]+/[^/]+/pull%-requests/[0-9]+.*/commits$")
      or string.match(url, "/[^/]+/[^/]+/pull%-requests/[0-9]+.*/diff$")
      or string.match(url, "/[^/]+/[^/]+/issues%?.*sort=")
      or string.match(url, "/[^/]+/[^/]+/issues%?.*component=")
      or string.match(url, "/[^/]+/[^/]+/issues%?.*milestone=")
      or string.match(url, "/[^/]+/[^/]+/issues%?.*version=")
      or string.match(url, "/[^/]+/[^/]+/issues%?.*priority=")
      or string.match(url, "/[^/]+/[^/]+/issues%?.*kind=")
      or string.match(url, "/[^/]+/[^/]+/issues%?.*responsible=")
      or string.match(url, "/[^/]+/[^/]+/downloads/%?tab=branches$")
      or string.match(url, "/[^/]+/[^/]+/downloads/%?tab=tags$")
      or string.match(url, "^https?://bitbucket%-connect%-icons%.s3%.amazonaws%.com/add%-on/icons/")
      or string.match(url, "^https?://[^/]*bitbucket%.org/account/signin/")
      or not (
        string.match(url, "^https?://[^/]*bitbucket%.org/")
        or string.match(url, "^https?://[^/]*bytebucket%.org/")
        or string.match(url, "^https?://[^/]*amazonaws%.com/")
      ) then
    return false
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end

  if parenturl ~= nil then
    local match = string.match(parenturl, "/downloads/%?tab=([a-zA-Z0-9]+)$")
    if match ~= nil and match == "tags"
      and (string.match(url, "/[^/]+/[^/]+/get/[^/]+%.zip$")
           or string.match(url, "/[^/]+/[^/]+/get/[^/]+%.tar%.gz$")) then
      return false
    end
  end

  if string.match(url, "^https?://[^/]+%.s3%.amazonaws%.com/.+[^/]$") then
    return true
  end

  local prev = nil
  for s in string.gmatch(url, "([0-9a-zA-Z%-%._]+)") do
    if prev ~= nil and prev .. "/" .. s == item_value then
      return true
    end
    prev = s
  end

  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if (downloaded[url] ~= true and addedtolist[url] ~= true)
     and (allowed(url, parent["url"]) or html == 0) then
    addedtolist[url] = true
    return true
  end
  
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(string.match(url, "^(.-)%.?$"), "&amp;", "&")
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
        and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)")..newurl)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    elseif string.match(newurl, "^%./") then
      checknewurl(string.match(newurl, "^%.(.+)"))
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
        or string.match(newurl, "^[/\\]")
        or string.match(newurl, "^%./")
        or string.match(newurl, "^[jJ]ava[sS]cript:")
        or string.match(newurl, "^[mM]ail[tT]o:")
        or string.match(newurl, "^vine:")
        or string.match(newurl, "^android%-app:")
        or string.match(newurl, "^ios%-app:")
        or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end

  if allowed(url, nil) and status_code == 200
    and not string.match(url, "^https?://[^/]*amazonaws%.com")
    and not string.match(url, "%.zip$")
    and not string.match(url, "%.tar%.gz$")
    and not string.match(url, "%.tar%.bz2$") then
    html = read_file(file)
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if status_code >= 300 and status_code <= 399 then
    local newloc = string.match(http_stat["newloc"], "^([^#]+)")
    if string.match(newloc, "^//") then
      newloc = string.match(url["url"], "^(https?:)") .. string.match(newloc, "^//(.+)")
    elseif string.match(newloc, "^/") then
      newloc = string.match(url["url"], "^(https?://[^/]+)") .. newloc
    elseif not string.match(newloc, "^https?://") then
      newloc = string.match(url["url"], "^(https?://.+/)") .. newloc
    end
    if downloaded[newloc] == true or addedtolist[newloc] == true or not allowed(newloc, url["url"]) then
      tries = 0
      return wget.actions.EXIT
    end
  end
  
  if status_code >= 200 and status_code <= 399 then
    local url_ctx = string.gsub(url["url"], "ctx=[0-9a-f]+", "ctx=removed")
    downloaded[url_ctx] = true
    downloaded[string.gsub(url_ctx, "https?://", "http://")] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500
      or (status_code >= 400 and status_code ~= 404 and status_code ~= 405 and status_code ~= 403)
      or status_code  == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 10
    if not allowed(url["url"], nil) then
        maxtries = 2
    end
    if tries > maxtries then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"], nil) then
        io.open("BANNED", "w"):close()
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end
