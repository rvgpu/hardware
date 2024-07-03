# docker image build -t rvgpu/eda:latest .

FROM phyzli/ubuntu18.04_xfce4_vnc4server_synopsys

RUN apt-get update && apt-get install -y git tigervnc-standalone-server python3-pip tcsh && rm -rf /var/lib/apt/lists/*

# setup environment for pytest
RUN echo "attrs==19.3.0" >> /root/requirements.txt ; \
    echo "importlib-metadata==1.3.0" >> /root/requirements.txt ; \
    echo "iniconfig==1.1.1" >> /root/requirements.txt ; \
    echo "more-itertools==8.0.2" >> /root/requirements.txt ; \
    echo "packaging==19.2" >> /root/requirements.txt ; \
    echo "pluggy==0.13.1" >> /root/requirements.txt ; \
    echo "py==1.10.0" >> /root/requirements.txt ; \
    echo "pyparsing==2.4.5" >> /root/requirements.txt ; \
    echo "pytest==5.3.2" >> /root/requirements.txt ; \
    echo "pytest-datafiles==2.0" >> /root/requirements.txt ; \
    echo "pytest-html==3.2.0" >> /root/requirements.txt ; \
    echo "pytest-metadata==1.11.0" >> /root/requirements.txt ; \
    echo "six==1.13.0" >> /root/requirements.txt ; \
    echo "tomli==1.2.3" >> /root/requirements.txt ; \
    echo "typing-extensions==4.1.1" >> /root/requirements.txt ; \
    echo "wcwidth==0.1.7" >> /root/requirements.txt ; \
    echo "zipp==0.6.0" >> /root/requirements.txt

RUN pip3 install --no-cache-dir -i https://mirrors.aliyun.com/pypi/simple/ -r /root/requirements.txt ; rm -f /root/requirements.txt

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
RUN echo '#!/bin/bash'  >> /usr/bin/start_vnc.sh ; \
    echo '# 启动 VNC server' >> /usr/bin/start_vnc.sh ; \
    echo 'vncserver $DISPLAY -rfbport $VNC_PORT -localhost no -PasswordFile ~/.vnc/passwd -geometry 1920x1080' >> /usr/bin/start_vnc.sh

RUN chmod +x /usr/bin/start_vnc.sh

WORKDIR /root
