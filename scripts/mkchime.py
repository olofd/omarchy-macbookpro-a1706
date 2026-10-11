import math, struct, wave, sys
SR = 44100
def bell(freq, dur, amp=0.5):
    n = int(SR * dur); out = []
    # a soft bell: fundamental plus a few harmonics, each fading at its own rate
    parts = [(1.0, 1.0, 4.0), (2.0, 0.22, 6.0), (3.0, 0.05, 9.0)]   # mostly the fundamental: warm, not shrill
    for i in range(n):
        t = i / SR
        a = min(1.0, t / 0.004)                    # 4 ms attack: no click
        v = sum(g * math.exp(-d * t) * math.sin(2 * math.pi * freq * m * t) for m, g, d in parts)
        out.append(amp * a * v)
    return out
def mix(base, add, at):
    start = int(at * SR)
    if len(base) < start + len(add): base += [0.0] * (start + len(add) - len(base))
    for i, v in enumerate(add): base[start + i] += v
    return base
def write(path, samples):
    peak = max(1e-9, max(abs(x) for x in samples)); k = 0.55 / peak
    w = wave.open(path, 'wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    fade = int(0.05 * SR)
    for i, x in enumerate(samples):
        f = min(1.0, (len(samples) - i) / fade)   # fade the tail to zero
        s = int(max(-1, min(1, x * k * f)) * 32767)
        w.writeframes(struct.pack('<hh', s, s))
    w.close()
plug = mix(bell(392.00, 1.3), bell(587.33, 1.5, 0.9), 0.18)   # G4, then D5: a low, rising "dong-ding"
write(sys.argv[1], plug)
unplug = bell(329.63, 1.0, 0.5)                                 # one soft E4
write(sys.argv[2], unplug)
