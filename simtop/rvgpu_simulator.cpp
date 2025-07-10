#include "rvgpu_simulator.hpp"
#include "rvgpu_simtop.hpp"
#include "../csim/rvgpu_csim.hpp"
#include "../rtlsim/rvgpu_rtlsim.hpp"
#include <iostream>
#include <memory>

rvgpu_simulator::rvgpu_simulator()
    : sim(std::make_unique<rvgpu_csim>())
{
}

rvgpu_simulator::rvgpu_simulator(RVGPU_SIM_TYPE sim_type, uint64_t vram_size)
{
    switch (sim_type)
    {
        case RVGPU_SIM_TYPE::RVGPU_CSIM:
            sim = std::make_unique<rvgpu_csim>(vram_size);
            break;
        case RVGPU_SIM_TYPE::RVGPU_RTLSIM:
            sim = std::make_unique<rvgpu_rtlsim>(vram_size);
            break;
        default:
            sim = std::make_unique<rvgpu_csim>(vram_size);
            break;
    }
}

uint32_t rvgpu_simulator::read_reg(RVGPU_REG reg)
{
    return sim->read_reg(static_cast<uint32_t>(reg));
}

void rvgpu_simulator::write_reg(RVGPU_REG reg, uint32_t data)
{
    sim->write_reg(static_cast<uint32_t>(reg), data);
}

uint32_t rvgpu_simulator::read_reg(uint32_t addr)
{
    return sim->read_reg(addr);
}

void rvgpu_simulator::write_reg(uint32_t addr, uint32_t data)
{
    sim->write_reg(addr, data);
}

bool rvgpu_simulator::wait_for_completion(uint32_t timeout_ms)
{
    return sim->wait_for_completion(timeout_ms);
}
 