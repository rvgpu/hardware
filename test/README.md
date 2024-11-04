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

# 运行单个测试并生成波形
pytest的输出默认输出到/tmp下，如果需要生成中间文件查看波形使用 svunit.py的脚本
```
./svunit.py ut/core/ut_rcore_iu_alu.sv
```

生成的中间数据在 out 目录下
