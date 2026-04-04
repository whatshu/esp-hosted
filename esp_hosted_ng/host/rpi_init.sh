#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright 2015-2021 Espressif Systems (Shanghai) PTE LTD
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

RESETPIN=""
BT_INIT_SET="0"
RAW_TP_MODE="0"
IF_TYPE="spi"
MODULE_NAME="esp32_${IF_TYPE}.ko"
# Raspberry Pi 5: BCM6 on the 40-pin header -> Linux GPIO 577
RPI_RESETPIN=577
OTA_FILE=""
SPI_BUS=0
SPI_CS=0
# Raspberry Pi 5 (RP1): BCM22/27 -> Linux GPIO 593/598
SPI_HS=593
SPI_DR=598

bringup_esp_wlan_interfaces()
{
	# Do not touch wlan0: on Pi 5 it is usually onboard brcmfmac (keep as your uplink).
	for dev in $(ip -o link show 2>/dev/null | awk -F': ' '/ wlan/{print $2}' | tr -d ' '); do
		[ "$dev" = "wlan0" ] && continue
		sudo ip link set "$dev" up 2>/dev/null || true
	done
}

wlan_init()
{
    if [ `lsmod | grep esp32 | wc -l` != "0" ]; then
        if [ `lsmod | grep esp32_sdio | wc -l` != "0" ]; then
            sudo rmmod esp32_sdio &> /dev/null
            else
            sudo rmmod esp32_spi &> /dev/null
        fi
    fi

    if [ "$CUSTOM_OPTS" != "" ] ; then
        echo "Adding $CUSTOM_OPTS"
    fi

    # For Linux other than Raspberry Pi, Please point
    # CROSS_COMPILE -> <Toolchain-Path>/bin/arm-linux-gnueabihf-
    # KERNEL        -> Place where kernel is checked out and built
    # ARCH          -> Architecture
    # make -j8 target=$IF_TYPE CROSS_COMPILE=/usr/bin/arm-linux-gnueabihf- KERNEL="/lib/modules/$(uname -r)/build" \
    # ARCH=arm64

    if [ "$AP_SUPPORT" = "1" ]; then
        echo "Setting CONFIG_AP_SUPPORT to y"
        CUSTOM_OPTS="${CUSTOM_OPTS} CONFIG_AP_SUPPORT=y"
    fi

    # Populate your arch if not populated correctly.
    arch_num_bits=$(getconf LONG_BIT)
    if [ "$arch_num_bits" = "32" ] ; then arch_found="arm"; else arch_found="arm64"; fi

    make -j8 target=$IF_TYPE KERNEL="/lib/modules/$(uname -r)/build" ARCH=$arch_found $CUSTOM_OPTS \

    if [ "$RESETPIN" = "" ] ; then
        # Default: BCM6 -> Linux GPIO 577 on Raspberry Pi 5
        if [ "$IF_TYPE" = "spi" ] ; then
            sudo insmod $MODULE_NAME resetpin=$RPI_RESETPIN raw_tp_mode=$RAW_TP_MODE ota_file=$OTA_FILE spi_bus=$SPI_BUS spi_cs=$SPI_CS spi_handshake=$SPI_HS spi_dataready=$SPI_DR
        else
            sudo insmod $MODULE_NAME resetpin=$RPI_RESETPIN raw_tp_mode=$RAW_TP_MODE ota_file=$OTA_FILE
        fi
    else
        #Use resetpin value from argument
        if [ "$IF_TYPE" = "spi" ] ; then
            sudo insmod $MODULE_NAME $RESETPIN raw_tp_mode=$RAW_TP_MODE ota_file=$OTA_FILE spi_bus=$SPI_BUS spi_cs=$SPI_CS spi_handshake=$SPI_HS spi_dataready=$SPI_DR
        else
            sudo insmod $MODULE_NAME $RESETPIN raw_tp_mode=$RAW_TP_MODE ota_file=$OTA_FILE
        fi
    fi

    if [ `lsmod | grep esp32 | wc -l` != "0" ]; then
        echo "esp32 module inserted "
		sleep 4
		bringup_esp_wlan_interfaces

        echo "ESP32 host init successfully completed"
    fi
}

bt_init()
{
    sudo pinctrl set 15 a0 pu
    sudo pinctrl set 14 a0 pu
    if [ "$BT_INIT_SET" = "4" ] ; then
        sudo pinctrl set 16 a3 pu
        sudo pinctrl set 17 a3 pu
    fi
}

usage()
{
    echo "This script prepares RPI for WLAN and BT/BLE operation over ESP32 device."
    echo "\nUsage: ./rpi_init.sh [arguments]"
    echo "\nArguments are optional and are as below:"
    echo "  spi:           sets ESP32<->RPI communication over SPI"
    echo "  sdio:          sets ESP32<->RPI communication over SDIO"
    echo "  btuart:        Set GPIO pins on RPI for HCI UART operations with TX, RX, CTS, RTS (defaulted to option btuart_4pins)"
    echo "  btuart_2pins:  Set GPIO pins on RPI for HCI UART operations with only TX & RX pins configured (only for ESP32-C2/C6)"
    echo "  resetpin=577: BCM6 on Raspberry Pi 5 -> Linux GPIO 577 (script default)"
    echo "  ap_support:     Enable access point support"
    echo "  spi_bus=<n>:    SPI bus number (default: 0)"
    echo "  spi_cs=<n>:     SPI chip select (default: 0)"
    echo "  spi_hs=<n>:     SPI handshake GPIO Linux number (default 593 = BCM22 on Pi 5)"
    echo "  spi_dr=<n>:     SPI data-ready GPIO Linux number (default 598 = BCM27 on Pi 5)"
    echo "\nExample:"
    echo "  - Prepare RPi for WLAN operation on SDIO. SDIO is default if no interface mentioned."
    echo "    # ./rpi_init.sh or ./rpi_init.sh sdio"
    echo "\n  - Use SPI for host<->ESP32 communication. SDIO is default if no interface mentioned."
    echo "    # ./rpi_init.sh spi"
    echo "\n  - Prepare RPi for BT/BLE operation over UART and WLAN over SDIO/SPI."
    echo "    # ./rpi_init.sh sdio btuart or ./rpi_init.sh spi btuart"
    echo "\n  - Use GPIO pin BCM5 (GPIO29) for reset."
    echo "    # ./rpi_init.sh resetpin=5"
    echo "\n  - Enable access point support."
    echo "    # ./rpi_init.sh <transport> ap_support"
    echo "\n  - Do btuart, using GPIO pin BCM5 (GPIO29) for reset over SDIO/SPI."
    echo "    # ./rpi_init.sh sdio btuart resetpin=5 or ./rpi_init.sh spi btuart resetpin=5"
    echo "\n  - set the OTA file path"
    echo "   # ./rpi_init.sh spi ota_file=/path/to/ota_file"
}

parse_arguments()
{
    while [ "$1" != "" ]; do
        case $1 in
            --help | -h )
                usage
                exit 0
                ;;
            sdio)
                IF_TYPE=$1
                ;;
            spi)
                IF_TYPE=$1
                ;;
            resetpin=*)
                echo "Received Option: $1"
                RESETPIN=$1
                ;;
            btuart | btuart_4pins | btuart_4pin)
                echo "Configure Host BT UART with 4 pins, RX, TX, CTS, RTS"
                BT_INIT_SET="4"
                ;;
            btuart_2pins | btuart_2pin)
                echo "Configure Host BT UART with 2 pins, RX & TX"
                BT_INIT_SET="2"
                ;;
            rawtp_host_to_esp)
                echo "Test RAW TP ESP to HOST"
                RAW_TP_MODE="1"
                ;;
            rawtp_esp_to_host)
                echo "Test RAW TP ESP to HOST"
                RAW_TP_MODE="2"
                ;;
            ap_support)
                echo "Enabling AP support"
                AP_SUPPORT="1"
                ;;
            ota_file=*)
                echo "Recvd Option: $1"
                OTA_FILE=${1#*=}
                ;;
            spi_bus=*)
                SPI_BUS=${1#*=}
                ;;
            spi_cs=*)
                SPI_CS=${1#*=}
                ;;
            spi_hs=*)
                SPI_HS=${1#*=}
                ;;
            spi_dr=*)
                SPI_DR=${1#*=}
                ;;
            *)
                echo "$1 : unknown option"
                usage
                exit 1
                ;;
        esac
        shift
    done
}

parse_arguments $*
if [ "$IF_TYPE" = "" ] ; then
    echo "Error: No protocol selected"
    usage
    exit 1
else
    echo "Building for $IF_TYPE protocol"
    MODULE_NAME=esp32_${IF_TYPE}.ko
fi

if [ "$IF_TYPE" = "spi" ] ; then
    # Only apply spidev_disabler if not already loaded (avoid stacking duplicate overlays)
    if ! dtoverlay -l 2>/dev/null | grep -q "spidev_disabler"; then
        rm -f spidev_disabler.dtbo
        # Disable default spidev driver
        dtc spidev_disabler.dts -O dtb > spidev_disabler.dtbo
        sudo dtoverlay -d . spidev_disabler
    fi
fi

if [ `lsmod | grep bluetooth | wc -l` = "0" ]; then
    echo "bluetooth module inserted"
    sudo modprobe bluetooth
fi

if [ `lsmod | grep cfg80211 | wc -l` = "0" ]; then
    echo "cfg80211 module inserted"
    sudo modprobe cfg80211
fi

if [ `lsmod | grep bluetooth | wc -l` != "0" ]; then
    wlan_init
fi

if [ "$BT_INIT_SET" != "0" ] ; then
    bt_init
fi


#alias load_module_sdio='sudo modprobe bluetooth; sudo modprobe cfg80211; sudo insmod ./esp32_sdio.ko resetpin=6; sleep 4;sudo ifconfig wlan0 up'
#alias load_module_spi='sudo dtoverlay spidev_disabler; sudo modprobe bluetooth; sudo modprobe cfg80211; sudo insmod ./esp32_spi.ko resetpin=6; sleep 4;sudo ifconfig wlan0 up'
