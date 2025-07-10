#ifndef RVGPU_CSIM_HPP
#define RVGPU_CSIM_HPP

#include "../simtop/rvgpu_simtop.hpp"
#include <vector>
#include <cstring>

//=============================================================================
// RVGPU CSim实现类
//=============================================================================

class rvgpu_csim : public rvgpu_simtop {
public:
    // 构造函数
    rvgpu_csim(uint64_t vram_size = 256 * 1024 * 1024);
    ~rvgpu_csim();

    // 寄存器访问接口
    uint32_t read_reg(uint32_t addr) override;
    void write_reg(uint32_t addr, uint32_t data) override;
    
    // 等待完成接口
    bool wait_for_completion(uint64_t timeout_ms = 5000) override;

    // 获取仿真类型
    RVGPU_SIM_TYPE get_sim_type() const override { return RVGPU_SIM_TYPE::RVGPU_CSIM; }

private:
    // 内部状态
    std::vector<uint32_t> registers;
    uint64_t vram_size;
    
    // GPU状态变量
    bool gpu_idle;
    bool task_complete;
};

#endif // RVGPU_CSIM_HPP 