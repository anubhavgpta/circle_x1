import math


HEAD_DIM = 64
PAIR_COUNT = HEAD_DIM // 2
POS_COUNT = 16
SCALE = 1 << 15


def q15_hex(value):
    quantized = int(round(value * SCALE))
    if quantized > 32767:
        quantized = 32767
    if quantized < -32768:
        quantized = -32768
    return f"{quantized & 0xFFFF:04x}"


def main():
    lines = []
    for dim_pair in range(PAIR_COUNT):
        theta = 1.0 / (10000.0 ** ((2.0 * dim_pair) / HEAD_DIM))
        for pos in range(POS_COUNT):
            angle = pos * theta
            lines.append(q15_hex(math.cos(angle)))
            lines.append(q15_hex(math.sin(angle)))

    with open("rope_lut.mem", "w", encoding="ascii") as handle:
        handle.write("\n".join(lines))
        handle.write("\n")

    print(f"generated rope_lut.mem with {len(lines)} lines")


if __name__ == "__main__":
    main()
