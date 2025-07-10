#ifndef RVGPU_SIMTOP_HPP
#define RVGPU_SIMTOP_HPP

#include <cstdint>

//=============================================================================
// 仿真类型枚举
//=============================================================================

enum class RVGPU_SIM_TYPE {
    RVGPU_CSIM,     // C++实现的CModel
    RVGPU_RTLSIM    // SystemVerilog仿真
};

//=============================================================================
// RVGPU仿真器虚基类
//=============================================================================

class rvgpu_simtop {
public:
    virtual ~rvgpu_simtop() = default;

    // 寄存器访问接口 - 原始地址版本
    virtual uint32_t read_reg(uint32_t addr) = 0;
    virtual void write_reg(uint32_t addr, uint32_t data) = 0;
    
    // 等待完成接口 - 毫秒单位
    virtual bool wait_for_completion(uint64_t timeout_ms = 5000) = 0; // 默认5秒

    // 获取仿真类型
    virtual RVGPU_SIM_TYPE get_sim_type() const = 0;

protected:
    // 构造函数
    rvgpu_simtop() = default;

private:
    // 禁止实例化基类
    rvgpu_simtop(const rvgpu_simtop&) = delete;
    rvgpu_simtop& operator=(const rvgpu_simtop&) = delete;
};

#endif // RVGPU_SIMTOP_HPP 