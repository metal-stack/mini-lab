import os
import paramiko
import sys

if len(sys.argv) != 2:
    print('usage: init.py <hostname>')
    exit()

leaf = sys.argv[1]

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(leaf, 22, 'admin', 'admin', allow_agent=False, look_for_keys=False)

sftp = paramiko.SFTPClient.from_transport(client.get_transport())
sftp.put('files/ssh/id_rsa.pub', '/home/admin/authorized_keys')

command = '''
      sudo mkdir -p /root/.ssh &&\
      sudo mv /home/admin/authorized_keys /root/.ssh &&\
      sudo chmod 600 /root/.ssh/authorized_keys &&\
      sudo chown root:root /root/.ssh/authorized_keys &&\
      sudo ztp disable -y
'''

_, _, _ = client.exec_command(command)

sftp.close()
client.close()
exit()
