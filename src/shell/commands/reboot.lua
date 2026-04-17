return function()
    print("Перезагрузка...")
    sleep(0.5)
    os.reboot()
    return 0
end
