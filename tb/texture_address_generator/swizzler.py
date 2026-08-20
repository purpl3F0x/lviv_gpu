def swizzler_10bit(address: int) -> int:
    # 10-bit mask (0x3FF = 1023)
    x_idx = address & 0x3FF
    y_idx = (address >> 10) & 0x3FF
    
    swz = 0
    for bit_idx in range(10):
        swz |= ((x_idx >> bit_idx) & 1) << (2 * bit_idx)
        swz |= ((y_idx >> bit_idx) & 1) << (2 * bit_idx + 1)
        
    return swz

l = [0x04060000]

for i in l:
    swz = swizzler_10bit(i)
    print(f"address: {i:08x}, swizzled: {swz: 08x}")