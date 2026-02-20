# Fedora Bootable Container for TeamSpeak Server
FROM quay.io/fedora/fedora-bootc:43

ARG TS3_VERSION=3.13.7

# Install packages, setup TeamSpeak, and configure system in one layer
WORKDIR /var/lib/teamspeak
RUN dnf update -y && \
    dnf install -y \
    wget \
    tar \
    bzip2 \
    sqlite \
    glibc.i686 \
    libstdc++.i686 \
    systemd \
    sudo \
    openssh-server \
    qemu-guest-agent \
    firewalld \
    audit \
    mariadb-connector-c \
    && dnf clean all \
    && printf '%s\n' \
    '# TeamSpeak Server System User' \
    'u teamspeak - "TeamSpeak Server" /var/lib/teamspeak /sbin/nologin' \
    > /usr/lib/sysusers.d/99-teamspeak.conf \
    && wget https://files.teamspeak-services.com/releases/server/${TS3_VERSION}/teamspeak3-server_linux_amd64-${TS3_VERSION}.tar.bz2 \
    && tar -xjf teamspeak3-server_linux_amd64-${TS3_VERSION}.tar.bz2 \
    && mkdir -p /opt/teamspeak3-server \
    && mv teamspeak3-server_linux_amd64/* /opt/teamspeak3-server/ \
    && rm -rf teamspeak3-server_linux_amd64 teamspeak3-server_linux_amd64-${TS3_VERSION}.tar.bz2 \
    && touch /var/lib/teamspeak/.ts3server_license_accepted

COPY config/teamspeak.service /etc/systemd/system/teamspeak.service
COPY config/configure-teamspeak.sh /usr/local/bin/configure-teamspeak.sh
COPY config/ts3server.ini /etc/teamspeak/ts3server.ini
RUN chmod +x /usr/local/bin/configure-teamspeak.sh

# Create directories, configure tmpfiles, enable services, and configure SSH in one layer
RUN systemctl enable teamspeak.service \
    && mkdir -p /etc/teamspeak \
    && mkdir -p /var/lib/teamspeak/{logs,files,database} \
    && mkdir -p /usr/lib/tmpfiles.d \
    && printf '%s\n' \
    '# TeamSpeak Server Directory Ownership' \
    'z /var/lib/teamspeak 0755 teamspeak teamspeak -' \
    'Z /var/lib/teamspeak 0755 teamspeak teamspeak -' \
    'z /etc/teamspeak 0755 teamspeak teamspeak -' \
    'd /var/lib/teamspeak/database 0755 teamspeak teamspeak -' \
    'd /var/lib/teamspeak/logs 0755 teamspeak teamspeak -' \
    'd /var/lib/teamspeak/files 0755 teamspeak teamspeak -' \
    > /usr/lib/tmpfiles.d/99-teamspeak.conf \
    && systemctl enable sshd \
    && systemctl enable qemu-guest-agent \
    && systemctl enable firewalld \
    && printf '%s\n' \
    '<?xml version="1.0" encoding="utf-8"?>' \
    '<service>' \
    '  <short>TeamSpeak 3</short>' \
    '  <description>TeamSpeak 3 voice, query, and file transfer ports</description>' \
    '  <port protocol="udp" port="9987"/>' \
    '  <port protocol="tcp" port="10011"/>' \
    '  <port protocol="tcp" port="30033"/>' \
    '</service>' \
    > /usr/lib/firewalld/services/teamspeak3.xml \
    && firewall-offline-cmd --add-service=teamspeak3 \
    && mkdir -p /etc/ssh/sshd_config.d \
    && printf '%s\n' \
    'PermitRootLogin no' \
    'PasswordAuthentication yes' \
    'PubkeyAuthentication yes' \
    'AuthorizedKeysFile .ssh/authorized_keys' \
    > /etc/ssh/sshd_config.d/99-bootc.conf

# Expose TeamSpeak ports
EXPOSE 9987/udp 10011 30033

# Use systemd as PID 1 for proper bootc behavior
CMD ["/sbin/init"]
