#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Community Add-on: Network UPS Tools
# Configures Network UPS Tools
# ==============================================================================
readonly USERS_CONF=/etc/nut/upsd.users
readonly UPSD_CONF=/etc/nut/upsd.conf
readonly UPS_CONF=/etc/nut/ups.conf
declare nutmode
declare password
declare shutdowncmd
declare upsmonpwd
declare username


DATA_PATH=$(bashio::config 'data_path')
SOCAT_MASTER=$(bashio::config 'socat.master')
SOCAT_SLAVE=$(bashio::config 'socat.slave')
SOCAT_OPTIONS=$(bashio::config 'socat.options')

#if bashio::config.true 'socat.enabled'; then
#    # Socat start configuration
#    bashio::log.blue "Socat startup parameters:"
#    bashio::log.blue "Options:     $SOCAT_OPTIONS"
#    bashio::log.blue "Master:      $SOCAT_MASTER"
#    bashio::log.blue "Slave:       $SOCAT_SLAVE"

#    bashio::log.info "Starting socat process ..."
#    exec socat $SOCAT_OPTIONS $SOCAT_MASTER $SOCAT_SLAVE &

#    bashio::log.debug "Modifying process for logging if required"
#    if bashio::config.true 'socat.log'; then
#        bashio::log.debug "Socat loggin enabled, setting file path to $DATA_PATH/socat.log"
#        exec &>"$DATA_PATH/socat.log" 2>&1
#    else
#        bashio::log.debug "No logging required"
#    fi
#fi

nutmode=$(bashio::config 'mode')
bashio::log.info "Setting mode to ${nutmode}..."
sed -i "s#%%nutmode%%#${nutmode}#g" /etc/nut/nut.conf

if bashio::config.true 'list_usb_devices' ;then
    bashio::log.info "Connected USB devices:"
    lsusb
fi

if bashio::config.equals 'mode' 'netserver' ;then
    bashio::log.info "Generating ${USERS_CONF}..."

    # Create Monitor User
    upsmonpwd=$(shuf -ze -n20  {A..Z} {a..z} {0..9}|tr -d '\0')
    {
        echo
        echo "[upsmonmaster]"
        echo "  password = ${upsmonpwd}"
        echo "  upsmon master"
    } >> "${USERS_CONF}"

    for user in $(bashio::config "users|keys"); do
        bashio::config.require.username "users[${user}].username"
        username=$(bashio::config "users[${user}].username")

        bashio::log.info "Configuring user: ${username}"
        if ! bashio::config.true 'i_like_to_be_pwned'; then
            bashio::config.require.safe_password "users[${user}].password"
        else
            bashio::config.require.password "users[${user}].password"
        fi
        password=$(bashio::config "users[${user}].password")

        {
            echo
            echo "[${username}]"
            echo "  password = ${password}"
        } >> "${USERS_CONF}"

        for instcmd in $(bashio::config "users[${user}].instcmds"); do
            echo "  instcmds = ${instcmd}" >> "${USERS_CONF}"
        done

        for action in $(bashio::config "users[${user}].actions"); do
            echo "  actions = ${action}" >> "${USERS_CONF}"
        done

        if bashio::config.has_value "users[${user}].upsmon"; then
            upsmon=$(bashio::config "users[${user}].upsmon")
            echo "  upsmon ${upsmon}" >> "${USERS_CONF}"
        fi
    done

    if bashio::config.has_value "upsd_maxage"; then
        maxage=$(bashio::config "upsd_maxage")
        echo "MAXAGE ${maxage}" >> "${UPSD_CONF}"
    fi

    if bashio::config.has_value "pollinterval"; then
        pollinterval=$(bashio::config "pollinterval")
        echo "pollinterval ${pollinterval}" >> "${UPS_CONF}"
        echo "" >> "${UPS_CONF}"
    fi

    for device in $(bashio::config "devices|keys"); do
        upsname=$(bashio::config "devices[${device}].name")
        upsdriver=$(bashio::config "devices[${device}].driver")
        upsport=$(bashio::config "devices[${device}].port")

        bashio::log.info "Configuring Device named ${upsname}..."
        {
            echo
            echo "[${upsname}]"
            echo "  driver = ${upsdriver}"
            echo "  port = ${upsport}"
        } >> /etc/nut/ups.conf

        OIFS=$IFS
        IFS=$'\n'
        for configitem in $(bashio::config "devices[${device}].config"); do
            echo "  ${configitem}" >> /etc/nut/ups.conf
        done
        IFS="$OIFS"

        echo "MONITOR ${upsname}@localhost 1 upsmonmaster ${upsmonpwd} master" \
            >> /etc/nut/upsmon.conf
    done
    
fi

shutdowncmd="\"s6-svscanctl -t /var/run/s6/services\""
if bashio::config.true 'shutdown_host'; then
    bashio::log.warning "UPS Shutdown will shutdown the host"
    shutdowncmd="/usr/bin/shutdownhost"
fi

echo "SHUTDOWNCMD  ${shutdowncmd}" >> /etc/nut/upsmon.conf
