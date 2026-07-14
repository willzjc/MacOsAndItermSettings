#!/bin/bash

alias battery=battery_power

# Battery power analysis function
battery_power() {
    # Get battery data from ioreg
    BATTERY_DATA=$(ioreg -r -n AppleSmartBattery | egrep 'IsCharging|ExternalConnected|Amperage|Voltage|CurrentCapacity|MaxCapacity|AdapterDetails')

    # Extract values (get first match only)
    IS_CHARGING=$(echo "$BATTERY_DATA" | grep '"IsCharging" =' | head -1 | awk '{print $3}')
    EXTERNAL_CONNECTED=$(echo "$BATTERY_DATA" | grep '"ExternalConnected" =' | head -1 | awk '{print $3}')
    AMPERAGE=$(echo "$BATTERY_DATA" | grep '"Amperage" =' | head -1 | awk '{print $3}')
    VOLTAGE=$(echo "$BATTERY_DATA" | grep '"Voltage" =' | head -1 | awk '{print $3}')
    CURRENT_CAPACITY=$(echo "$BATTERY_DATA" | grep '"CurrentCapacity" =' | head -1 | awk '{print $3}')
    MAX_CAPACITY=$(echo "$BATTERY_DATA" | grep '"MaxCapacity" =' | head -1 | awk '{print $3}')

    # Extract adapter details from AdapterDetails (first match, single line)
    ADAPTER_LINE=$(echo "$BATTERY_DATA" | grep '"AdapterDetails"' | head -1)
    ADAPTER_VOLTAGE=$(echo "$ADAPTER_LINE" | grep -o '"AdapterVoltage"=[0-9]*' | head -1 | cut -d= -f2)
    ADAPTER_CURRENT=$(echo "$ADAPTER_LINE" | grep -o ',"Current"=[0-9]*' | head -1 | cut -d= -f2)
    if [ -z "$ADAPTER_CURRENT" ]; then
        ADAPTER_CURRENT=$(echo "$ADAPTER_LINE" | grep -o '"Current"=[0-9]*' | head -1 | cut -d= -f2)
    fi
    ADAPTER_WATTS=$(echo "$ADAPTER_LINE" | grep -o '"Watts"=[0-9]*' | head -1 | cut -d= -f2)
    ADAPTER_DESC=$(echo "$ADAPTER_LINE" | grep -o '"Description"="[^"]*"' | head -1 | cut -d'"' -f4)

    # Convert Amperage from two's complement if needed (values > 2^63 are negative)
    # Use bc for large number handling
    if [ -n "$AMPERAGE" ]; then
        # Check if value is > 2^63 (9223372036854775808)
        # Two's complement: if value > 2^63, then it's negative: value - 2^64
        COMPARE=$(echo "$AMPERAGE > 9223372036854775807" | bc)
        if [ "$COMPARE" = "1" ]; then
            AMPERAGE_MA=$(echo "$AMPERAGE - 18446744073709551616" | bc)
        else
            AMPERAGE_MA="$AMPERAGE"
        fi
    else
        AMPERAGE_MA=""
    fi

    # Convert to proper units
    if [ -n "$VOLTAGE" ]; then
        VOLTAGE_V=$(echo "scale=3; $VOLTAGE / 1000" | bc)
    else
        VOLTAGE_V=""
    fi
    if [ -n "$AMPERAGE_MA" ] && [ "$AMPERAGE_MA" != "" ]; then
        AMPERAGE_A=$(echo "scale=3; $AMPERAGE_MA / 1000" | bc)
    else
        AMPERAGE_A=""
    fi

    # Calculate battery power (negative = draining, positive = charging)
    if [ -n "$AMPERAGE_MA" ] && [ -n "$VOLTAGE" ]; then
        BATTERY_POWER_W=$(echo "scale=2; $AMPERAGE_A * $VOLTAGE_V" | bc)
    else
        BATTERY_POWER_W="N/A"
    fi

    # Calculate adapter power
    if [ -n "$ADAPTER_VOLTAGE" ] && [ -n "$ADAPTER_CURRENT" ]; then
        ADAPTER_VOLTAGE_V=$(echo "scale=3; $ADAPTER_VOLTAGE / 1000" | bc)
        ADAPTER_CURRENT_A=$(echo "scale=3; $ADAPTER_CURRENT / 1000" | bc)
        ADAPTER_POWER_CALC=$(echo "scale=2; $ADAPTER_VOLTAGE_V * $ADAPTER_CURRENT_A" | bc)
    else
        ADAPTER_POWER_CALC="N/A"
    fi

    # Calculate charge percentage
    if [ -n "$CURRENT_CAPACITY" ] && [ -n "$MAX_CAPACITY" ]; then
        CHARGE_PERCENT=$(echo "scale=1; ($CURRENT_CAPACITY / $MAX_CAPACITY) * 100" | bc)
    else
        CHARGE_PERCENT="N/A"
    fi

    # Determine power flow status
    if [ "$EXTERNAL_CONNECTED" = "Yes" ]; then
        if [ -n "$ADAPTER_WATTS" ]; then
            CHARGER_POWER_VAL="$ADAPTER_WATTS"
            CHARGER_POWER="$ADAPTER_WATTS W"
        elif [ -n "$ADAPTER_POWER_CALC" ] && [ "$ADAPTER_POWER_CALC" != "N/A" ]; then
            CHARGER_POWER_VAL="$ADAPTER_POWER_CALC"
            CHARGER_POWER="$ADAPTER_POWER_CALC W"
        else
            CHARGER_POWER_VAL=""
            CHARGER_POWER="Unknown"
        fi
    else
        CHARGER_POWER_VAL="0"
        CHARGER_POWER="0 W (Not Connected)"
    fi

    # Calculate system consumption (always positive - total power being used)
    # System consumption = Charger power - Battery power
    # (Battery power is negative when draining, positive when charging)
    if [ "$BATTERY_POWER_W" != "N/A" ] && [ -n "$BATTERY_POWER_W" ] && [ -n "$CHARGER_POWER_VAL" ] && [ "$CHARGER_POWER_VAL" != "" ]; then
        SYSTEM_CONSUMPTION=$(echo "scale=2; $CHARGER_POWER_VAL - $BATTERY_POWER_W" | bc)
        # Ensure it's always positive (absolute value)
        SYSTEM_CONSUMPTION_SIGN=$(echo "$SYSTEM_CONSUMPTION < 0" | bc -l)
        if [ "$SYSTEM_CONSUMPTION_SIGN" = "1" ]; then
            SYSTEM_CONSUMPTION=$(echo "scale=2; -1 * $SYSTEM_CONSUMPTION" | bc)
        fi
    elif [ "$BATTERY_POWER_W" != "N/A" ] && [ -n "$BATTERY_POWER_W" ]; then
        # No charger, system is running on battery only
        SYSTEM_CONSUMPTION=$(echo "scale=2; -1 * $BATTERY_POWER_W" | bc)
        # Ensure it's always positive
        SYSTEM_CONSUMPTION_SIGN=$(echo "$SYSTEM_CONSUMPTION < 0" | bc -l)
        if [ "$SYSTEM_CONSUMPTION_SIGN" = "1" ]; then
            SYSTEM_CONSUMPTION=$(echo "scale=2; -1 * $SYSTEM_CONSUMPTION" | bc)
        fi
    else
        SYSTEM_CONSUMPTION="N/A"
    fi

    # Format numbers to ensure leading zeros
    format_number() {
        local num="$1"
        if [[ "$num" =~ ^\.[0-9]+$ ]]; then
            echo "0$num"
        else
            echo "$num"
        fi
    }

    # Print table
    echo "================================================================"
    echo "                    BATTERY POWER ANALYSIS"
    echo "================================================================"
    echo ""
    echo "Status:"
    printf "  External Connected: %s\n" "$EXTERNAL_CONNECTED"
    printf "  Is Charging:        %s\n" "$IS_CHARGING"
    printf "  Charge Level:       %s%% (%s/%s)\n" "$CHARGE_PERCENT" "$CURRENT_CAPACITY" "$MAX_CAPACITY"
    echo "------------------------------------------------------------"
    echo ""
    echo "Charger Input:"
    if [ "$EXTERNAL_CONNECTED" = "Yes" ] && [ -n "$ADAPTER_VOLTAGE" ] && [ -n "$ADAPTER_CURRENT" ]; then
        printf "  Adapter:            %s\n" "${ADAPTER_DESC:-Unknown}"
        printf "  Voltage:            %s V (%s mV)\n" "${ADAPTER_VOLTAGE_V}" "${ADAPTER_VOLTAGE}"
        printf "  Current:            %s A (%s mA)\n" "${ADAPTER_CURRENT_A}" "${ADAPTER_CURRENT}"
        printf "  Power:              %s\n" "$CHARGER_POWER"
    else
        printf "  Power:              %s\n" "$CHARGER_POWER"
    fi
    echo "------------------------------------------------------------"
    echo ""
    echo "Battery:"
    if [ -n "$VOLTAGE" ]; then
        printf "  Voltage:            %s V (%s mV)\n" "${VOLTAGE_V}" "${VOLTAGE}"
    fi
    if [ -n "$AMPERAGE_MA" ]; then
        printf "  Current:            %s A (%s mA)\n" "${AMPERAGE_A}" "${AMPERAGE_MA}"
    fi
    if [ "$BATTERY_POWER_W" != "N/A" ] && [ -n "$BATTERY_POWER_W" ]; then
        POWER_SIGN=$(echo "$BATTERY_POWER_W < 0" | bc -l)
        BATTERY_POWER_FORMATTED=$(format_number "$BATTERY_POWER_W")
        if [ "$POWER_SIGN" = "1" ]; then
            printf "  Power:              %s W (Draining)\n" "$BATTERY_POWER_FORMATTED"
        else
            printf "  Power:              %s W (Charging)\n" "$BATTERY_POWER_FORMATTED"
        fi
    else
        printf "  Power:              N/A\n"
    fi
    echo "------------------------------------------------------------"
    echo ""
    echo "System Consumption:"
    if [ "$SYSTEM_CONSUMPTION" != "N/A" ] && [ -n "$SYSTEM_CONSUMPTION" ]; then
        SYSTEM_CONSUMPTION_FORMATTED=$(format_number "$SYSTEM_CONSUMPTION")
        printf "  Total Power Being Used: %s W\n" "$SYSTEM_CONSUMPTION_FORMATTED"
        if [ "$EXTERNAL_CONNECTED" = "Yes" ] && [ -n "$CHARGER_POWER_VAL" ] && [ "$CHARGER_POWER_VAL" != "" ] && [ "$CHARGER_POWER_VAL" != "0" ]; then
            if [ "$BATTERY_POWER_W" != "N/A" ] && [ -n "$BATTERY_POWER_W" ]; then
                POWER_SIGN=$(echo "$BATTERY_POWER_W < 0" | bc -l)
                if [ "$POWER_SIGN" = "1" ]; then
                    # Battery is draining (negative), so we use absolute value
                    BATTERY_ABS=$(echo "scale=2; -1 * $BATTERY_POWER_W" | bc)
                    BATTERY_ABS_FORMATTED=$(format_number "$BATTERY_ABS")
                    printf "    - From Charger:    %s W\n" "$CHARGER_POWER"
                    printf "    - From Battery:    %s W (draining)\n" "$BATTERY_ABS_FORMATTED"
                else
                    # Battery is charging (positive)
                    BATTERY_ABS_FORMATTED=$(format_number "$BATTERY_POWER_W")
                    CHARGER_TO_SYSTEM=$(echo "scale=2; $CHARGER_POWER_VAL - $BATTERY_POWER_W" | bc)
                    CHARGER_TO_SYSTEM_FORMATTED=$(format_number "$CHARGER_TO_SYSTEM")
                    printf "    - Total from Charger: %s\n" "$CHARGER_POWER"
                    printf "      * To System:      %s W\n" "$CHARGER_TO_SYSTEM_FORMATTED"
                    printf "      * To Battery:     %s W (charging)\n" "$BATTERY_ABS_FORMATTED"
                fi
            else
                printf "    - From Charger:    %s W\n" "$CHARGER_POWER"
            fi
        else
            printf "    - From Battery:    %s W\n" "$SYSTEM_CONSUMPTION_FORMATTED"
        fi
    else
        printf "  Total Power Usage:   N/A\n"
    fi
    echo "================================================================"
}
