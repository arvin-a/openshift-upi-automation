#!/usr/bin/env python

import random

def random_bytes(num=6):
    return [random.randrange(256) for _ in range(num)]

def generate_mac(uaa=False, multicast=False, oui=None, separator=':', byte_fmt='%02x'):
    mac = random_bytes()
    if oui:
        if type(oui) == str:
            oui = [int(chunk) for chunk in oui.split(separator)]
        mac = oui + random_bytes(num=6-len(oui))
    else:
        if multicast:
            mac[0] |= 1 # set bit 0
        else:
            mac[0] &= ~1 # clear bit 0
        if uaa:
            mac[0] &= ~(1 << 1) # clear bit 1
        else:
            mac[0] |= 1 << 1 # set bit 1
    
    rmac=separator.join(byte_fmt % b for b in mac)
    return rmac

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--uaa', action='store_true', help='generates a universally administered address (instead of LAA otherwise)')
    parser.add_argument('--multicast', action='store_true', help='generates a multicast MAC (instead of unicast otherwise)')
    parser.add_argument('--oui', default="00:50:56", help='enforces a specific organizationally unique identifier (like 00:60:2f for Cisco)')
    parser.add_argument('--byte-fmt', default='%02x', help='The byte format. Set to %02X for uppercase hex formatting.')
    parser.add_argument('--separator', default=':', help="The byte separator character. Defaults to ':'.")
    parser.add_argument('--qty', default=1, help="Number of addresses to generate")
    args = parser.parse_args()

    for n in range(int(args.qty)):
        print(generate_mac(oui=args.oui, uaa=args.uaa, multicast=args.multicast, separator=args.separator, byte_fmt=args.byte_fmt))

if __name__ == '__main__':
    main()