return function()
    print("Выключение...")
    sleep(0.5)
    os.shutdown()
    return 0
end
