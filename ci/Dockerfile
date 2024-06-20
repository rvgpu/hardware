# docker image build -t rvgpu/eda:latest .

FROM phyzli/ubuntu18.04_xfce4_vnc4server_synopsys

RUN apt-get update && apt-get install -y git tigervnc-standalone-server python3-pip tcsh && rm -rf /var/lib/apt/lists/*
RUN pip3 install --no-cache-dir pytest -i https://mirrors.aliyun.com/pypi/simple/

# setup Synopsys Licence
ENV SYNOPSYS_DIR="/home/synopsys"
ENV SNPSLMD_LICENSE_FILE=27000@10.100.101.47
ENV LM_LICENSE_FILE="${SYNOPSYS_DIR}/Liscen/Synopsys.dat"

# Setup SVUNIT
RUN cd /root; git clone https://github.com/svunit/svunit.git
ENV SVUNIT_INSTALL=/root/svunit
ENV PATH="$SVUNIT_INSTALL/bin:${PATH}"

# Setup VNC
RUN mkdir -p /root/.vnc
COPY ./passwd /root/.vnc/

ENV DISPLAY=:1  
ENV VNC_PORT=5901 
RUN echo '#!/bin/bash'  >> /usr/bin/start_vnc.sh  && \
    echo '# 启动 VNC server' >> /usr/bin/start_vnc.sh  && \
    echo 'vncserver $DISPLAY -rfbport $VNC_PORT -localhost no -PasswordFile ~/.vnc/passwd -geometry 1920x1080' >> /usr/bin/start_vnc.sh

RUN chmod +x /usr/bin/start_vnc.sh

WORKDIR /root
