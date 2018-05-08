#!/usr/bin/env tarantool

local system = {}

function system.reverse_table(t)
   local reversedTable = {}
   local itemCount = #t
   for k, v in ipairs(t) do
       reversedTable[itemCount + 1 - k] = v
   end
   return reversedTable
end

function system.round(value, rounds)
   return tonumber(string.format("%."..(tostring(rounds or 2)).."f", value))
end


return system
