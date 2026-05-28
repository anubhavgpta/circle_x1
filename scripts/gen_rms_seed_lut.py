import math
from pathlib import Path

SEED_COUNT = 64
SCALE = 1 << 15   # Q1.15
OUT_PATH = Path("src") / "rtl" / "rms_seed_lut.mem"


def q1p15_hex(value):
    quantized = int(round(value * SCALE))
    if quantized > 32767:
        quantized = 32767
    if quantized < 0:
        quantized = 0
    return f"{quantized:04x}"


def main():
    lines = []
    for i in range(SEED_COUNT):
        if i == 0:
            lines.append("7fff")   # epsilon: rsqrt(~0) = max Q1.15
        else:
            lines.append(q1p15_hex(1.0 / math.sqrt(i)))

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w", encoding="ascii") as handle:
        handle.write("\n".join(lines))
        handle.write("\n")

    print(f"Generated rms_seed_lut.mem: {len(lines)} entries")


if __name__ == "__main__":
    main()
