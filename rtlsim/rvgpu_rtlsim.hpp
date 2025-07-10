#ifndef RVGPU_RTLSIM_HPP
#define RVGPU_RTLSIM_HPP

#include "../simtop/rvgpu_simtop.hpp"
#include <string>
#include <memory>

//=============================================================================
// RVGPU RTLSim实现类
//=============================================================================

class rvgpu_rtlsim : public rvgpu_simtop {
public:
    // 构造函数
    rvgpu_rtlsim(uint64_t vram_size = 256 * 1024 * 1024);
    ~rvgpu_rtlsim();

    // 寄存器访问接口
    uint32_t read_reg(uint32_t addr) override;
    void write_reg(uint32_t addr, uint32_t data) override;
    
    // 等待完成接口
    bool wait_for_completion(uint64_t timeout_ms = 5000) override;

    // 获取仿真类型
    RVGPU_SIM_TYPE get_sim_type() const override { return RVGPU_SIM_TYPE::RVGPU_RTLSIM; }

private:
    // SystemVerilog仿真相关
    bool sv_initialized;
    bool sv_ready;
    uint64_t vram_size;
    
    // SystemVerilog仿真句柄（这里使用void*作为占位符）
    void* sv_sim_handle;
    void* sv_gpu_handle;
    void* sv_memory_handle;
    
    // 内部方法
    bool initialize_sv_simulation();
    void finalize_sv_simulation();
    bool is_sv_ready() const;
    bool connect_to_sv_simulation();
    void disconnect_from_sv_simulation();
    bool send_command_to_sv(const std::string& command);
    std::string receive_response_from_sv();
    
    // 命令格式
    struct sv_command {
        std::string cmd_type;
        uint32_t addr;
        uint32_t data;
        uint64_t mem_addr;
        uint32_t size;
    };
    
    std::string format_command(const sv_command& cmd);
    bool parse_response(const std::string& response, uint32_t& data);
};

#endif // RVGPU_RTLSIM_HPP 