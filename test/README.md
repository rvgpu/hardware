# How to run test
安装环境：
```
pip3 install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/
```

运行全部的测试用力使用：
```
pytest
```

如果运行一个testsuite的话使用：
```
pytest -s test_core_int.py
```

如果运行一个testsuite里面的单个testcase使用：
```
pytest -s test_core_int.py::test_rcore_iu_top
```

pytest 参数的含义：
- -s: 相当于--capture=no，pytest不捕捉终端显示，将详细的log显示在终端上
- test_*.py: test_*py的测试
