# echo "\`define RVGPU_HARDWARE_TOPPATH_STR \"${RVGPU_HARDWARE}\"" > project.v

export RVGPU_HARDWARE=/root/hardware
pushd /root/svunit
source Setup.bsh
popd

runSVUnit -s vcs -t ut_rcore_iu_alu.sv -o out -c -debug_access+all
