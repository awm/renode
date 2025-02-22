*** Keywords ***
Create Machine With Button And LED
    [Arguments]              ${firmware}  ${usart}=2  ${button_port}=B  ${button_pin}=2  ${led_port}=A  ${led_pin}=5
    IF  "${firmware}" == "button"
        Execute Command          $bin = @https://dl.antmicro.com/projects/renode/b_l072z_lrwan1--zephyr-button.elf-s_402204-2343dc7268dedc253893a84300f3dbd02bc63a2a
    ELSE IF  "${firmware}" == "blinky"
        Execute Command          $bin = @https://dl.antmicro.com/projects/renode/b_l072z_lrwan1--zephyr-blinky.elf-s_395652-4d2c6106335435629d3611d2a732e37ca9f17eeb
    ELSE IF  "${firmware}" == "led_shell"
        Execute Command          $bin = @https://dl.antmicro.com/projects/renode/b_l072z_lrwan1--zephyr-led_shell.elf-s_1471160-5398b2ac0ab1c71ec144eba55f4840d86ddb921a
    ELSE
        Fail                     Unknown firmware '${firmware}'
    END
    Execute Command          include @scripts/single-node/stm32l072.resc
    Execute Command          machine LoadPlatformDescriptionFromString "gpioPort${led_port}: { ${led_pin} -> led@0 }; led: Miscellaneous.LED @ gpioPort${led_port} ${led_pin}"
    Execute Command          machine LoadPlatformDescriptionFromString "button: Miscellaneous.Button @ gpioPort${button_port} ${button_pin} { invert: true; -> gpioPort${button_port}@${button_pin} }"

    Create Terminal Tester   sysbus.usart${usart}
    Create LED Tester        sysbus.gpioPort${led_port}.led  defaultTimeout=2

Emulation Should Be Paused
    ${st}=                   Execute Command  emulation IsStarted
    Should Contain           ${st}  False

Emulation Should Be Paused At Time
    [Arguments]              ${time}
    Emulation Should Be Paused
    ${ts}=                   Execute Command  machine GetTimeSourceInfo
    Should Contain           ${ts}  Elapsed Virtual Time: ${time}

Emulation Should Not Be Paused
    ${st}=                   Execute Command  emulation IsStarted
    Should Contain           ${st}  True

*** Test Cases ***
Terminal Tester Assert Should Start Emulation
    Create Machine With Button And LED  button

    Emulation Should Be Paused

    Wait For Line On Uart    Press the button

    Emulation Should Not Be Paused

Terminal Tester Assert Should Not Start Emulation If Matching String Has Already Been Printed
    Create Machine With Button And LED  button

    # Give the sample plenty of virtual time to print the string
    Execute Command          emulation RunFor "0.1"

    Emulation Should Be Paused At Time  00:00:00.100000

    Wait For Line On Uart    Press the button

    Emulation Should Be Paused At Time  00:00:00.100000

Terminal Tester Assert Should Precisely Pause Emulation
    Create Machine With Button And LED  button

    Wait For Line On Uart    Press the button  pauseEmulation=true

    Execute Command          gpioPortB.button Press

    ${l}=                    Wait For Line On Uart  Button pressed at (\\d+)  pauseEmulation=true  treatAsRegex=true
    Should Be Equal          ${l.groups[0]}  6401

    Emulation Should Be Paused At Time  00:00:00.000226
    PC Should Be Equal       0x8002c08  # this is the STR that writes to TDR in LL_USART_TransmitData8

Quantum Should Not Impact Tester Pause PC
    Create Machine With Button And LED  button
    Execute Command          emulation SetGlobalQuantum "0.010000"

    Wait For Line On Uart    Press the button  pauseEmulation=true

    Execute Command          gpioPortB.button Press

    Wait For Line On Uart    Button pressed at (\\d+)  pauseEmulation=true  treatAsRegex=true

    PC Should Be Equal       0x8002c08

LED Tester Assert Should Start Emulation Unless The State Already Matches
    Create Machine With Button And LED  blinky

    # The LED state is false by default on reset because it is not inverted, so this assert
    # should pass immediately without starting the emulation
    Assert LED State         false
    Emulation Should Be Paused At Time  00:00:00.000000

    # And this one should start the emulation
    Assert LED State         true
    Emulation Should Not Be Paused

LED Tester Assert Should Not Start Emulation With Timeout 0
    Create Machine With Button And LED  blinky

    # The LED state is false by default, so this assert should fail immediately without
    # starting the emulation because the timeout is 0
    Run Keyword And Expect Error  *LED assertion not met*  Assert LED State  true  0

    Emulation Should Be Paused At Time  00:00:00.000000

LED Tester Assert Should Precisely Pause Emulation
    Create Machine With Button And LED  blinky

    Assert LED State         true  pauseEmulation=true
    Emulation Should Be Paused At Time  00:00:00.000120
    PC Should Be Equal       0x8002a46  # this is the STR that writes to BSRR in gpio_stm32_port_set_bits_raw

    Assert LED State         false  pauseEmulation=true
    Emulation Should Be Paused At Time  00:00:01.000211
    PC Should Be Equal       0x80028a2  # this is the STR that writes to BRR in LL_GPIO_ResetOutputPin

    Provides                 synced-blinky

LED Tester Assert And Hold Should Precisely Pause Emulation
    Requires                 synced-blinky

    # The expected times have 3 decimal places because the default quantum is 0.000100
    ${state}=                Set Variable  False
    FOR  ${i}  IN RANGE  2  5
        Assert And Hold LED State  ${state}  timeoutAssert=1  timeoutHold=1  pauseEmulation=true
        Emulation Should Be Paused At Time  00:00:0${i}.000
        ${state}=                Evaluate  not ${state}
    END

LED Tester Assert Is Blinking Should Precisely Pause Emulation
    Requires                 synced-blinky

    Assert LED Is Blinking   testDuration=5  onDuration=1  offDuration=1  pauseEmulation=true
    Emulation Should Be Paused At Time  00:00:06.000300

LED Tester Assert Duty Cycle Should Precisely Pause Emulation
    Requires                 synced-blinky

    Assert LED Duty Cycle    testDuration=5  expectedDutyCycle=0.5  pauseEmulation=true
    Emulation Should Be Paused At Time  00:00:06.000300

LED And Terminal Testers Should Cooperate
    Create Machine With Button And LED  led_shell

    Wait For Prompt On Uart  $  pauseEmulation=true
    Write Line To Uart       led on leds 0  waitForEcho=false
    Wait For Line On Uart    leds: turning on LED 0  pauseEmulation=true
    Emulation Should Be Paused At Time  00:00:00.001239
    PC Should Be Equal       0x800b26a
    # The LED should not be turned on yet: the string is printed before actually changing the GPIO
    Assert LED State         false  0

    # Now wait for the LED to turn on
    Assert LED State         true  pauseEmulation=true
    Emulation Should Be Paused At Time  00:00:00.001243
    PC Should Be Equal       0x800af0a
