--
-- Copyright (C) 2014-2022 Masatoshi Fukunaga
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
local floor = math.floor
local type = type
local new_redis = require('redis').new
local new_cache = require('cache').new
-- constants
local INF_POS = math.huge

--- is_uint
--- @param x any
--- @return boolean
local function is_uint(x)
    return type(x) == 'number' and x >= 0 and x < INF_POS and floor(x) == x
end

--- @class cache.redis
--- @field ttl integer
--- @field port? string|integer
--- @field host? string
local Cache = {}

--- init
--- @param ttl integer
--- @param host? string
--- @param port? string|integer
--- @return cache.redis
function Cache:init(ttl, host, port)
    if host ~= nil and type(host) ~= 'string' then
        error('host must be string')
    elseif port ~= nil and type(port) ~= 'string' and not is_uint(port) then
        error('port must be string or uint')
    end
    self.host = host
    self.port = port
    self.pool = setmetatable({}, {
        __mode = 'k',
    })
    return new_cache(self, ttl)
end

--- @class redis

--- getconn
--- @return redis
function Cache:getconn()
    local pc = next(self.pool)
    if pc then
        self.pool[pc] = nil
        return pc
    end
    return new_redis(self.host, self.port)
end

--- putconn
--- @param c redis
function Cache:putconn(c)
    self.pool[c] = true
end

--- set
--- @param key string
--- @param val string
--- @param ttl integer
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Cache:set(key, val, ttl)
    local c, err, timeout = self:getconn()
    if not c then
        return false, err, timeout
    end

    local res
    res, err, timeout = c:setex(key, ttl, val)
    if not res then
        c:quit()
        return false, err, timeout
    end
    self:putconn(c)

    if res.error then
        return false, res.message
    end
    return true
end

--- get
--- @param key string
--- @param ttl integer
--- @return string? val
--- @return any err
--- @return boolean? timeout
function Cache:get(key, ttl)
    local c, err, timeout = self:getconn()
    if not c then
        return nil, err, timeout
    end

    local res
    if ttl then
        res, err, timeout = c:getex(key, 'EX', ttl)
    else
        res, err, timeout = c:get(key)
    end

    if not res then
        c:quit()
        return nil, err, timeout
    end
    self:putconn(c)

    if res.error then
        return nil, res.message
    end
    return res.message
end

--- delete
--- @param key string
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Cache:delete(key)
    local c, err, timeout = self:getconn()
    if not c then
        return false, err, timeout
    end

    local res
    res, err, timeout = c:del(key)
    if not res then
        c:quit()
        return false, err, timeout
    end
    self:putconn(c)

    if res.error then
        return false, res.error
    end
    return res.message ~= 0
end

--- rename
--- @param oldkey string
--- @param newkey string
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Cache:rename(oldkey, newkey)
    local c, err, timeout = self:getconn()
    if not c then
        return false, err, timeout
    end

    local res
    res, err, timeout = c:renamenx(oldkey, newkey)
    if not res then
        c:quit()
        return false, err, timeout
    end
    self:putconn(c)

    if res.error then
        return false
    end
    return res.message == 1
end

--- keys
--- @param callback fun(string):(boolean,any)
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Cache:keys(callback, ...)
    local c, err, timeout = self:getconn()
    if not c then
        return false, err, timeout
    end

    local res
    res, err, timeout = c:scan(0, ...)
    while res do
        for _, k in ipairs(res.message[2]) do
            local ok
            ok, err = callback(k)
            if not ok then
                if err ~= nil then
                    return false, err
                end
                return true
            end
        end

        if res.message[1] == '0' then
            break
        end
        res, err, timeout = c:scan(res.message[1], ...)
    end
    if err then
        c:quit()
        return false, err, timeout
    end
    self:putconn(c)

    return true
end

--- evict
--- @return integer nevict
function Cache:evict()
    return 0
end

return {
    new = require('metamodule').new(Cache),
}
