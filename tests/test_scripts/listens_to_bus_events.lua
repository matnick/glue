function event_handler(value)

    local test_value

    if (value == "specific_value") then
        test_value = "success"
    else
        test_value = "reverted"
    end

    update("/test/event_script/current_status", test_value)

end