#!/usr/bin/env tarantool
local bus = {}
local bus_private = {}

local inspect = require 'libs/inspect'
local clock = require 'clock'
local json = require 'json'
local box = box

local scripts_busevents = require 'scripts_busevents'
local scripts_drivers = require 'scripts_drivers'
local system = require 'system'
local fiber = require 'fiber'
local logger = require 'logger'
local config = require 'config'

bus.TYPE = {SHADOW = "SHADOW", NORMAL = "NORMAL"}
bus.check_flag = {CHECK_VALUE = "CHECK_VALUE"}

bus.fifo_saved_rps = 0
bus.bus_saved_rps = 0
bus.max_fifo_count = 0

------------------↓ Private functions ↓------------------


function bus_private.fifo_storage_worker()
   while true do
      local topic, value, shadow_flag, source_uuid = bus_private.get_value_from_fifo()
      if (value ~= nil and topic ~= nil) then
         if (shadow_flag == bus.TYPE.NORMAL) then
            scripts_busevents.process(topic, value, source_uuid)
            scripts_drivers.process(topic, value, source_uuid)
         end
         local timestamp = os.time()
         bus.storage:upsert({topic, value, timestamp, "", {}, "false"}, {{"=", 2, value} , {"=", 3, timestamp}})
         bus.bus_saved_rps = bus.bus_saved_rps + 1
         fiber.yield()
      else
         fiber.sleep(0.1)
      end
   end
end

function bus_private.bus_rps_stat_worker()
   fiber.sleep(2)
   while true do
      if (bus.bus_saved_rps >= 15) then bus.bus_saved_rps = bus.bus_saved_rps - 15 end
      bus.set_value("/glue/bus/fifo_saved", bus.fifo_saved_rps/5)
      bus.set_value("/glue/bus/bus_saved", bus.bus_saved_rps/5)
      bus.set_value("/glue/bus/fifo_max", bus.max_fifo_count)
      bus.fifo_saved_rps = 0
      bus.bus_saved_rps = 0
      fiber.sleep(5)
   end
end

function bus_private.add_value_to_fifo(topic, value, shadow_flag, source_uuid, update_time)
   if (topic ~= nil and value ~= nil and shadow_flag ~= nil and source_uuid ~= nil) then
      value = tostring(value)
      local id = bus_private.gen_fifo_id(update_time)
      bus.fifo_storage:insert{id, topic, value, shadow_flag, source_uuid}
      bus.fifo_saved_rps = bus.fifo_saved_rps + 1
      return true
   end
   return false
end

function bus_private.get_value_from_fifo()
   local tuple = bus.fifo_storage.index.timestamp:min()
   if (tuple ~= nil) then
      bus.fifo_storage.index.timestamp:delete(tuple['timestamp'])
      local count = bus.fifo_storage.index.timestamp:count()
      if (count > bus.max_fifo_count) then bus.max_fifo_count = count end
      return tuple['topic'], tuple["value"], tuple['shadow_flag'], tuple["source_uuid"]
   end
end

function bus_private.get_tags(table_tags)
   local string_tags = ""
   for i, tag in pairs(table_tags) do
      string_tags = string_tags..tag
      if (i ~= #table_tags) then
         string_tags = string_tags..", "
      end
   end
   return string_tags
end

function bus_private.update_type(topic, type)
   if (topic ~= nil and type ~= nil and bus.storage.index.topic:get(topic) ~= nil) then
      bus.storage.index.topic:update(topic, {{"=", 4, type}})
      return true
   else
      return false
   end
end

function bus_private.update_tags(topic, tags)
   if (topic ~= nil and tags ~= nil and bus.storage.index.topic:get(topic) ~= nil) then
      local processed_tags = tags:gsub("%%20", " ")
      processed_tags = processed_tags:gsub(" ", "")
      local table_tags = setmetatable({}, {__serialize = 'array'})
      for tag in processed_tags:gmatch("([^,]+)") do
         local copy_flag = false
         for _, table_tag in pairs(table_tags) do
            if (tag == table_tag) then copy_flag = true end
         end
         if (copy_flag == false) then table.insert(table_tags, tag) end
      end
      bus.storage.index.topic:update(topic, {{"=", 5, table_tags}})
      return true
   else
      return false
   end
end

function bus_private.delete_topics(topic)
   if (topic ~= nil) then
      if (topic == "*") then
         bus.storage:truncate()
      else
         bus.storage.index.topic:delete(topic)
      end
      return true
   end
   return false
end

function bus_private.gen_fifo_id(update_time)
   local current_time = update_time or clock.realtime()
   local new_id = current_time*10000
   while bus.fifo_storage.index.timestamp:get(new_id) do
      new_id = new_id + 1
   end
   return new_id
end

------------------↓ Public functions ↓------------------

function bus.init()

   ---------↓ Space "storage"(main bus storage) ↓---------
   local format = {
      {name='topic',        type='string'},   --1
      {name='value',        type='string'},   --2
      {name='update_time',  type='number'},   --3
      {name='type',         type='string'},   --4
      {name='tags',         type='array'},    --5
      {name='tsdb',         type='string'},   --6
   }
   bus.storage = box.schema.space.create('storage', {if_not_exists = true, format = format, id = config.id.bus})
   bus.storage:create_index('topic', {parts = {'topic'}, if_not_exists = true})



   ---------↓ Space "fifo_storage"(fifo storage) ↓---------
   local fifo_format = {
      {name='timestamp',      type='number'},   --1
      {name='topic',          type='string'},   --2
      {name='value',          type='string'},   --3
      {name='shadow_flag',    type='string'},   --4
      {name='source_uuid',    type='string'},   --5
   }
   bus.fifo_storage = box.schema.space.create('fifo_storage', {if_not_exists = true, temporary = true, format = fifo_format, id = config.id.bus_fifo})
   bus.fifo_storage:create_index('timestamp', {parts={'timestamp'}, if_not_exists = true})


   --------- End storage's config ---------

   fiber.create(bus_private.fifo_storage_worker)
   fiber.create(bus_private.bus_rps_stat_worker)

   local http_system = require 'http_system'
   http_system.endpoint_config("/system_bus", bus.http_api_handler)

   bus.storage:upsert({"/glue/bus/fifo_saved", "0", os.time(), "record/sec", {"system"}, "false"}, {{"=", 2, "0"} , {"=", 3, os.time()}})
   bus.storage:upsert({"/glue/bus/bus_saved", "0", os.time(), "record/sec", {"system"}, "false"}, {{"=", 2, "0"} , {"=", 3, os.time()}})
   bus.storage:upsert({"/glue/bus/fifo_max", "0", os.time(), "records", {"system"}, "false"}, {{"=", 2, "0"} , {"=", 3, os.time()}})
end

function bus.set_value_generator(uuid)
   return function(topic, value, check_flag, update_time)
      if (check_flag == bus.check_flag.CHECK_VALUE) then
         if (bus.get_value(topic) ~= tostring(value)) then
            return bus_private.add_value_to_fifo(topic, value, bus.TYPE.NORMAL, uuid, update_time)
         end
      else
         return bus_private.add_value_to_fifo(topic, value, bus.TYPE.NORMAL, uuid, update_time)
      end
   end
end

function bus.set_value(topic, value)
   return bus_private.add_value_to_fifo(topic, value, bus.TYPE.NORMAL, "0")
end

function bus.shadow_set_value(topic, value)
   return bus_private.add_value_to_fifo(topic, value, bus.TYPE.SHADOW, "0")
end

function bus.get_value(topic)
   local tuple = bus.storage.index.topic:get(topic)

   if (tuple ~= nil) then
      return tuple["value"], tuple["update_time"], tuple["type"], tuple["tags"]
   else
      return nil
   end
end

function bus.serialize(pattern)
   local bus_table = {}

   for _, tuple in bus.storage.index.topic:pairs() do
      local topic = tuple["topic"].."/"
      local subtopic, _, local_table

      if (topic:find(pattern or "")) then
         local_table = bus_table
         repeat
            _, _, subtopic, topic = topic:find("/(.-)(/.*)")
            if (subtopic ~= nil) then
               local_table[subtopic] = local_table[subtopic] or {}
               local_table = local_table[subtopic]
            end
         until subtopic == nil or topic == nil
         local_table.value = tuple["value"]
         local_table.update_time = tuple["update_time"]
         local_table.topic = tuple["topic"]
         local_table.type = tuple["type"]
         local_table.tags = tuple["tags"]
      end
   end
   return bus_table
end


function bus.serialize_v2(pattern)
   local bus_table = {}

   for _, tuple in bus.storage.index.topic:pairs() do
      local topic = tuple["topic"].."/"
      local subtopic, _, local_table

      if (topic:find(pattern or "")) then
         local_table = bus_table
         repeat
            _, _, subtopic, topic = topic:find("/(.-)(/.*)")
            if (subtopic ~= nil and subtopic ~= "") then
               local_table[subtopic] = local_table[subtopic] or {}
               local_table = local_table[subtopic]
            end
         until subtopic == nil or topic == nil
         local_table.__data__ = {}
         local_table.__data__.value = tuple["value"]
         local_table.__data__.update_time = tuple["update_time"]
         local_table.__data__.topic = tuple["topic"]
         local_table.__data__.type = tuple["type"]
         local_table.__data__.tags = bus_private.get_tags(tuple["tags"])
      end
   end
   return bus_table
end

function bus.http_api_handler(req)
   local params = req:param()
   local return_object

   if (params["action"] == "update_value") then
      if (params["topic"] == nil or params["value"] == nil) then
         return_object = req:render{ json = { result = false, msg = "No valid param topic or value" } }
      else
         local result = bus.set_value(params["topic"], params["value"])
         return_object = req:render{ json = { result = result } }
      end

   elseif (params["action"] == "update_type") then
      if (params["topic"] == nil or params["type"] == nil) then
         return_object = req:render{ json = { result = false, msg = "No valid param topic or type" } }
      else
         local result = bus_private.update_type(params["topic"], params["type"])
         return_object = req:render{ json = { result = result } }
      end

   elseif (params["action"] == "update_tags") then
      if (params["topic"] == nil or params["tags"] == nil) then
         return_object = req:render{ json = { result = false, msg = "No valid param topic or tags" } }
      else
         local result = bus_private.update_tags(params["topic"], params["tags"])
         return_object = req:render{ json = { result = result } }
      end

   elseif (params["action"] == "delete_topics") then
      if (params["topic"] == nil) then
         return_object = req:render{ json = { result = false, msg = "No valid param topic" } }
      else
         local result = bus_private.delete_topics(params["topic"])
         return_object = req:render{ json = { result = result } }
      end

   elseif (params["action"] == "get_bus_serialized") then
      local bus_data = bus.serialize(params["pattern"])
      return_object = req:render{ json = { bus = bus_data } }

   elseif (params["action"] == "get_bus_serialized_v2") then
      local bus_data = bus.serialize_v2(params["pattern"])
      return_object = req:render{ json = { bus = bus_data } }

   elseif (params["action"] == "get_bus") then
      local data_object = {}
      for _, tuple in bus.storage.index.topic:pairs() do
         local topic = tuple["topic"]
         local time = tuple["update_time"]
         local value = tuple["value"]
         local type = tuple["type"]
         local tags = bus_private.get_tags(tuple["tags"])
         table.insert(data_object, {topic = topic, time = time, value = value, type = type, tags = tags})
         if (params["limit"] ~= nil and tonumber(params["limit"]) <= #data_object) then break end
      end

      if (#data_object > 0) then
         return_object = req:render{ json =  data_object  }
      else
         return_object = req:render{ json = { none_data = "true" } }
      end

   else
      return_object = req:render{ json = {result = false, error_msg = "Bus API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Bus API: Unknown error(214)"} }
   return system.add_headers(return_object)
end

return bus


