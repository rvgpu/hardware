# How to run test

```
export RVGPU_HARDWARE=/root/hardware

pip3 install -r requirements -i https://mirrors.aliyun.com/pypi/simple/

pytest -s test_core_int.py
```

pytest 参数的含义：
- -s: 相当于--capture=no，pytest不捕捉终端显示，将详细的log显示在终端上
- test_*.py: test_*py的测试
