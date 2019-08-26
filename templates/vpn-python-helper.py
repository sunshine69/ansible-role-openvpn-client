#!{{ ansible_python_interpreter | default('/usr/bin/python3') }}

import pyotp, os

os.chdir("{{ vpn_remote_dir }}")

os.system("rm -f {{ vpn_client_profile_name }}.pass")

fc = """s
{{ vpn_client_pin }}%s
""" % pyotp.TOTP('{{ vpn_client_otp_password }}').now()
with open('{{ vpn_client_profile_name }}.pass','w') as pf:
    pf.write(fc)

os.system("chmod 0600 {{ vpn_client_profile_name }}.pass")
os.execvpe("openvpn", ["openvpn", "{{ vpn_client_profile_name }}.ovpn"], os.environ)
