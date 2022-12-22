require('luacov')
local testcase = require('testcase')
local sleep = require('testcase.timer').sleep
local new_cache_redis = require('cache.redis').new
local new_redis = require('redis').new

function testcase.before_each()
    local c = assert(new_redis())
    c:flushall()
    c:quit()
end

function testcase.new()
    -- test that returns an instance of cache
    assert(new_cache_redis(10))

    -- test that throws an error if ttl is invalid
    local err = assert.throws(new_cache_redis, 0)
    assert.match(err, 'ttl must be positive-integer')

    -- test that throws an error if host is invalid
    err = assert.throws(new_cache_redis, 1, {})
    assert.match(err, 'host must be string')

    -- test that throws an error if port is invalid
    err = assert.throws(new_cache_redis, 1, 'localhost', {})
    assert.match(err, 'port must be string or uint')
    err = assert.throws(new_cache_redis, 1, 'localhost', -1)
    assert.match(err, 'port must be string or uint')
end

function testcase.set()
    local c = assert(new_cache_redis(2))

    -- test that set a value associated with key
    assert(c:set('foo', 'bar'))
    assert.equal(c:get('foo'), 'bar')

    -- test that set a value associated with key and ttl
    assert(c:set('foo', 'world', 1))
    assert.equal(c:get('foo'), 'world')

    -- test that return an error if value is invalid
    local ok, err = c:set('foo', {
        inf = 0 / 0,
    })
    assert.is_false(ok)
    assert.equal(err, 'nan or inf number is not allowed')
end

function testcase.get()
    local c = assert(new_cache_redis(2))
    assert(c:set('foo', 'hello', 1))
    assert(c:set('bar', 'world'))

    -- test that get a value associated with key
    assert.equal(c:get('foo'), 'hello')

    -- test that get a value associated with key and set the lifetime
    assert.equal(c:get('foo', 1), 'hello')

    -- test that return nil after reached to ttl
    sleep(1)
    assert.is_nil(c:get('foo'))
    assert.equal(c:get('bar'), 'world')
    sleep(1)
    assert.is_nil(c:get('bar'))

    -- test that throws an error if key is invalid
    local err = assert.throws(c.get, c, 'foo bar')
    assert.match(err, 'key must be string of "^[a-zA-Z0-9_%-]+$"')

    -- test that throws an error if touch is invalid
    err = assert.throws(c.get, c, 'foobar', {})
    assert.match(err, 'ttl must be uint')
end

function testcase.delete()
    local c = assert(new_cache_redis(2))

    -- test that delete a value associated with key
    assert(c:set('foo', 'bar'))
    assert.equal(c:get('foo'), 'bar')
    assert.is_true(c:delete('foo'))
    assert.is_nil(c:get('foo'))

    -- test that return false if a value associated with key not found
    assert.is_false(c:delete('foo'))
end

function testcase.rename()
    local c = assert(new_cache_redis(2))

    -- test that rename an oldkey to newkey
    assert(c:set('foo', 'bar'))
    assert(c:rename('foo', 'newfoo'))
    assert.is_nil(c:get('foo'))
    assert.equal(c:get('newfoo'), 'bar')

    -- test that return false if a value associated with key not found
    assert.is_false(c:rename('foo', 'bar'))
end

function testcase.keys()
    local c = assert(new_cache_redis(10))
    assert(c:set('hello', 'b'))
    assert(c:set('world', 'b'))
    assert(c:set('foo', 'a'))
    assert(c:set('bar', 'b'))
    assert(c:set('baz', 'c'))

    -- test that return true
    local keys = {}
    assert.is_true(c:keys(function(k)
        keys[#keys + 1] = k
        return true
    end))
    table.sort(keys)
    assert.equal(keys, {
        'bar',
        'baz',
        'foo',
        'hello',
        'world',
    })

    -- test that abort by false
    keys = {}
    assert.is_true(c:keys(function(k)
        keys[#keys + 1] = k
        return #keys < 3
    end))
    assert.equal(#keys, 3)

    -- test that abort by error
    keys = {}
    local ok, err = c:keys(function(k)
        keys[#keys + 1] = k
        if #keys < 3 then
            return true
        end
        return false, 'abort by error'
    end)
    assert.is_false(ok)
    assert.equal(err, 'abort by error')
end

function testcase.evict()
    local c = assert(new_cache_redis(4))
    -- test that evict method always return 0
    assert.equal(c:evict(function()
    end), 0)
end
