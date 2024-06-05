# docker image build -t rvgpu/eda:latest .

FROM phyzli/ubuntu18.04_xfce4_vnc4server_synopsys

RUN apt-get update && apt-get install -y git tigervnc-standalone-server && rm -rf /var/lib/apt/lists/*

# Setup SVUNIT
RUN cd /root; git clone https://github.com/svunit/svunit.git

# Setup VNC
RUN mkdir -p /root/.vnc
COPY ./passwd /root/.vnc/

ENV DISPLAY=:1  
ENV VNC_PORT=5901 
RUN echo '#!/bin/bash'  >> /usr/bin/start_vnc.sh  && \
    echo '# 启动 VNC server' >> /usr/bin/start_vnc.sh  && \
    echo 'vncserver $DISPLAY -rfbport $VNC_PORT -localhost no -PasswordFile ~/.vnc/passwd' >> /usr/bin/start_vnc.sh

RUN chmod +x /usr/bin/start_vnc.sh
