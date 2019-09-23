#!{{ ansible_python_interpreter | default('/usr/bin/python3') }}

import pyotp, os

os.chdir("{{ vpn_remote_dir }}")

os.system("rm -f {{ vpn_client_profile_name }}.pass")

{% if vpn_client_otp_password is defined and vpn_client_otp_password != '' %}
otp_token = pyotp.TOTP('{{ vpn_client_otp_password }}').now()
{% else %}
otp_token = ''
{% endif %}

fc = """%s
{{ vpn_client_password }}%s
""" % (vpn_client_username, otp_token)
with open('{{ vpn_client_profile_name }}.pass','w') as pf:
    pf.write(fc)

os.system("chmod 0600 {{ vpn_client_profile_name }}.pass")
os.execvpe("openvpn", ["openvpn", "{{ vpn_client_profile_name }}.ovpn"], os.environ)
