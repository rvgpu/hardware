#ifndef RVGPU_SIMULATOR_HPP
#define RVGPU_SIMULATOR_HPP

#include "rvgpu_simtop.hpp"
#include "rvgpu_registers.hpp"
#include <memory>

enum class RVGPU_REG : uint32_t;

class rvgpu_simulator {
public:
    rvgpu_simulator();
    rvgpu_simulator(RVGPU_SIM_TYPE sim_type, uint64_t vram_size);

    uint32_t read_reg(RVGPU_REG reg);
    void write_reg(RVGPU_REG reg, uint32_t data);

    uint32_t read_reg(uint32_t addr);
    void write_reg(uint32_t addr, uint32_t data);

    bool wait_for_completion(uint32_t timeout_ms = 5000);

private:
    std::unique_ptr<rvgpu_simtop> sim;
};

#endif // RVGPU_SIMULATOR_HPP 