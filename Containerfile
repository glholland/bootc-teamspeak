# Fedora Bootable Container for TeamSpeak Server
FROM quay.io/fedora/fedora-bootc:43

ARG TS3_VERSION=3.13.7

# Install packages, setup TeamSpeak, and configure system in one layer
WORKDIR /opt
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
    cloud-init \
    firewalld \
    audit \
    && dnf clean all \
    && printf '%s\n' \
    '# TeamSpeak Server System User' \
    'u teamspeak - "TeamSpeak Server" /var/lib/teamspeak /sbin/nologin' \
    > /usr/lib/sysusers.d/99-teamspeak.conf \
    && wget https://files.teamspeak-services.com/releases/server/${TS3_VERSION}/teamspeak3-server_linux_amd64-${TS3_VERSION}.tar.bz2 \
    && tar -xjf teamspeak3-server_linux_amd64-${TS3_VERSION}.tar.bz2 \
    && mv teamspeak3-server_linux_amd64 teamspeak3-server \
    && rm teamspeak3-server_linux_amd64-3.13.7.tar.bz2 \
    && touch /opt/teamspeak3-server/.ts3server_license_accepted

# Create systemd service file for TeamSpeak
COPY config/teamspeak.service /etc/systemd/system/teamspeak.service

# Create directories, configure tmpfiles, enable services, and configure SSH in one layer
RUN systemctl enable teamspeak.service \
    && mkdir -p /etc/teamspeak \
    && mkdir -p /var/lib/teamspeak/{logs,files,database} \
    && mkdir -p /opt/teamspeak3-server/{logs,files,database} \
    && mkdir -p /usr/lib/tmpfiles.d \
    && printf '%s\n' \
    '# TeamSpeak Server Directory Ownership' \
    'z /opt/teamspeak3-server 0755 teamspeak teamspeak -' \
    'Z /opt/teamspeak3-server 0755 teamspeak teamspeak -' \
    'z /var/lib/teamspeak 0755 teamspeak teamspeak -' \
    'Z /var/lib/teamspeak 0755 teamspeak teamspeak -' \
    'z /etc/teamspeak 0755 teamspeak teamspeak -' \
    'd /var/lib/teamspeak/database 0755 teamspeak teamspeak -' \
    'd /var/lib/teamspeak/logs 0755 teamspeak teamspeak -' \
    'd /var/lib/teamspeak/files 0755 teamspeak teamspeak -' \
    > /usr/lib/tmpfiles.d/99-teamspeak.conf \
    && sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config \
    && systemctl enable sshd \
    && systemctl enable qemu-guest-agent \
    && systemctl enable firewalld \
    && mkdir -p /etc/ssh/sshd_config.d \
    && printf '%s\n' \
    'PermitRootLogin no' \
    'PasswordAuthentication yes' \
    'PubkeyAuthentication yes' \
    'AuthorizedKeysFile .ssh/authorized_keys' \
    > /etc/ssh/sshd_config.d/99-bootc.conf

# Copy custom configuration if provided
COPY config/ /etc/teamspeak/

# Expose TeamSpeak ports
EXPOSE 9987/udp 10011 30033

# Set up bootc to use systemd as init
WORKDIR /opt/teamspeak3-server

# Use systemd as PID 1 for proper bootc behavior
CMD ["/sbin/init"]
