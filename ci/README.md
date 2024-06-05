docker image build -t rvgpu/eda:latest .

docker run -it --name 自己定义 -p 5901:5901 -p 6080:6080 -v ./hardware:/root/hardware --hostname lizhen --mac-address 02:42:ac:11:00:02 rvgpu/eda
