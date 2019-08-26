#!/bin/sh

if ! `ps -ef|grep openvpn | grep -v grep | grep 'openvpn {{ vpn_client_profile_name }}.ovpn' >/dev/null 2>&1`; then
    echo "VPN has stopped. Trying to re-connect ..."
    exec {{ vpn_remote_dir }}/{{ vpn_client_profile_name }}.py
fi
