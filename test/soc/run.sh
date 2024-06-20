# echo "\`define RVGPU_HARDWARE_TOPPATH_STR \"${RVGPU_HARDWARE}\"" > project.v

export RVGPU_HARDWARE=/root/hardware
export RVGPU_HW_TEST_SOC=${RVGPU_HARDWARE}/test/soc

pushd /root/svunit
source Setup.bsh
popd

runSVUnit -s vcs -t tb_soc.sv -o out -c -debug_access+all
