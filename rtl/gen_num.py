from random import random
from random import seed
import sys
a = 0
seed(12345)
for i in range (50000):
    if (i % 50 == 0):
        val=random()
        a=a+50;
        if(val>0.5):
            a=a-64;


    a=a+8
    value = a
    padding = 8
    # to_print = f"{value:#0{padding}x}"
    to_print = '0x{0:0{1}x}'.format(value,padding)
    print(to_print[2:])
