# 1. build image
```
docker image build -f vcslic.df -t rvgpu/vcslic:latest .
```

# 2. Start VCS License Server
```
# docker run -it --hostname vcslic --mac-address 02:42:ad:11:00:00 rvgpu/vcslic
docker run --network bridge -it --privileged --hostname vcslic --mac-address fa:c9:e3:9a:bb:00 -p 27000:27000 -p 43095:43095 rvgpu/vcslic
```

# 3. Start Docker VCS
command as: 
```
# docker container rm -f zaceda
# docker run -it --hostname lizhen --mac-address 02:42:ac:11:00:02 phyzli/ubuntu18.04_xfce4_vnc4server_synopsys
# docker run -it --name eda -p 5901:5901 -p 6080:6080 -v ./hardware:/root/hardware --hostname lizhen --mac-address 02:42:ac:11:00:02 phyzli/ubuntu18.04_xfce4_vnc4server_synopsys
docker run -it --name zaceda  -p 5950:5901 -v ./hardware:/root/hardware rvgpu/eda
```

# reference
- https://zhuanlan.zhihu.com/p/433125915
- https://www.fasteda.cn/post/243.html
