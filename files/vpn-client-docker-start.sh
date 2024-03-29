#!/bin/sh

# Run from root cron job like this
# /home/ubuntu/src/xvt-jenkins/scripts/jenkins-vpn.sh <vpn_profile_file_name> [<ACTION>]
# It will start a openvpn container to connect to the vpn
# ACTION default to `start`, it can be start/stop/restart.
# The other container can use the network using docker option --net=container:<container_name>

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "SCRIPT_DIR: $SCRIPT_DIR"

JENKINS_VPN_PROFILE_FILE_NAME=${JENKINS_VPN_PROFILE_FILE_NAME:-$1}
JENKINS_VPN_PROFILE_NAME=$(basename $JENKINS_VPN_PROFILE_FILE_NAME .ovpn)
DOCKER_UTIL_IMAGE='xvtsolutions/alpine-python3-aws-ansible:2.8.4'
DOCKER_OPENVPN_IMAGE='dperson/openvpn-client'

. $SCRIPT_DIR/${JENKINS_VPN_PROFILE_NAME}.config

# The config file above should define at least the below vars
#JENKINS_VPN_USERNAME=
#JENKINS_VPN_PASSWORD=
#JENKINS_OTP_PASSWORD=

JENKIN_VPN_CONTAINER_NAME=$(basename $JENKINS_VPN_PROFILE_FILE_NAME .ovpn)

# Quit if there is one script already running
[ -f "/tmp/$JENKIN_VPN_CONTAINER_NAME" ] && exit 0

echo "Container name: $JENKIN_VPN_CONTAINER_NAME"
touch /tmp/$JENKIN_VPN_CONTAINER_NAME
trap "rm -f /tmp/$JENKIN_VPN_CONTAINER_NAME" EXIT

vpn_status=$(docker inspect --format='{{json .State.Status}}' $JENKIN_VPN_CONTAINER_NAME 2>/dev/null)

if [ "$vpn_status" = '"exited"' ]; then
    docker rm -f $JENKIN_VPN_CONTAINER_NAME
fi

WORKSPACE=${WORKSPACE:-$SCRIPT_DIR}

ACTION=${ACTION:-$2}
[ -z "$ACTION" ] && ACTION="start"

if [ -f "/.dockerenv" ]; then
    DOCKER_VOL_OPT="--volumes-from xvt_jenkins"
else
    DOCKER_VOL_OPT="-v ${WORKSPACE}:${WORKSPACE}"
fi

start_vpn() {
    reset_count=0
    while [ $reset_count -lt 5 ]; do
        echo "0 - Status: $vpn_status"
        if [ "$vpn_status" != '"healthy"' ] && [ "$vpn_status" != '"starting"' ] && [ "$vpn_status" != 'completed' ]; then
            reset_count=$((reset_count+1))
            if [ ! -z "${JENKINS_OTP_PASSWORD}" ]; then
                OTP_CODE=$(docker run --rm --entrypoint python3 ${DOCKER_UTIL_IMAGE} -c "import pyotp; print(pyotp.TOTP('$JENKINS_OTP_PASSWORD').now())")
            else
                OTP_CODE=''
            fi
            cat <<EOF > $WORKSPACE/$JENKIN_VPN_CONTAINER_NAME.pass
${JENKINS_VPN_USERNAME}
${JENKINS_VPN_PASSWORD}${OTP_CODE}
EOF
            chmod 0600 $WORKSPACE/$JENKIN_VPN_CONTAINER_NAME.pass
            docker run --rm --entrypoint sed $DOCKER_VOL_OPT --workdir $WORKSPACE ${DOCKER_UTIL_IMAGE} -i "s/auth\-user\-pass.*\$/auth-user-pass $JENKIN_VPN_CONTAINER_NAME.pass/g" $JENKINS_VPN_PROFILE_FILE_NAME

            vpn_status=$(docker inspect --format='{{json .State.Health.Status}}' $JENKIN_VPN_CONTAINER_NAME 2>/dev/null)
            echo "1 - Status: $vpn_status"
            if [ "$vpn_status" = '"healthy"' ] || [ "$vpn_status" = 'completed' ]; then
              echo "container already started and status is healthy"
            else
              echo "Start vpn container $JENKIN_VPN_CONTAINER_NAME ..."
                  docker rm -f $JENKIN_VPN_CONTAINER_NAME || true
                  docker run -d --name $JENKIN_VPN_CONTAINER_NAME $DOCKER_VOL_OPT \
                    --cap-add=NET_ADMIN --workdir $WORKSPACE \
                    --device /dev/net/tun ${DOCKER_OPENVPN_IMAGE} \
                    openvpn $JENKINS_VPN_PROFILE_FILE_NAME

              echo Wait maximum 5 minutes until the vpn status is healthy
              c=0
              while [ $c -lt 60 ]; do
                vpn_status=$(docker inspect --format='{{json .State.Status}}' $JENKIN_VPN_CONTAINER_NAME 2>/dev/null)
                if [ "$vpn_status" = '"healthy"' ]; then
                #if `docker logs --tail 5 $JENKIN_VPN_CONTAINER_NAME | grep 'Initialization Sequence Completed' >/dev/null 2>&1`; then
                    #echo "Got Initialization Sequence Completed"
                    echo "Container state is healthy"
                    vpn_status='completed'
                    break
                else
                if [ $c -ge 20 ]; then
                    echo "CRITICAL ERROR. Container is not healthy after 5 minutes, aborting"
                    docker rm -f $JENKIN_VPN_CONTAINER_NAME || true
                    break
                fi
                c=$((c+1))
                sleep 5
                fi
              done
            fi
        else
            # To stay on and re-check after 120 sec set reset_count=0. To quit
            # set it to something > 5. If we spawn from cron better to quit
            # here
            reset_count=100
            if [ $reset_count -lt 5 ]; then
                sleep 120
            fi
            vpn_status=$(docker inspect --format='{{json .State.Status}}' $JENKIN_VPN_CONTAINER_NAME 2>/dev/null)
        fi
    done
}

stop_vpn() {
      killall jenkins-vpn.sh
      docker stop $JENKIN_VPN_CONTAINER_NAME || true
      rm -f $WORKSPACE/$JENKIN_VPN_CONTAINER_NAME.pass
}

restart_vpn() {
    stop_vpn
    sleep 5
    start_vpn
}

case $ACTION in
    start)
        start_vpn;
        ;;
    stop)
        stop_vpn;
        ;;
    restart)
        restart_vpn;
        ;;
    *)
        echo "Uknown $ACTION"
        ;;
esac
