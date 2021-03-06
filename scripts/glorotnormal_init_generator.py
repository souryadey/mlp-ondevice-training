#==============================================================================
# Given fi, fo, int_bits and frac_bits for some network config, generate Glorot Normal initialization files for weights and biases
# Default files are in binary and decimal
# Additional function convert2hex converts them to hexadecimal (0s are added as MSBs if needed)
# Sourya Dey, USC
#==============================================================================

import numpy as np
import os

def glorotnormal_init_generate(fi, fo, int_bits, frac_bits, numentries=2000, filename='s136_frc21_int10'):
    filename_bin = os.path.dirname(os.path.dirname(os.path.realpath('__file__'))) + '/gaussian_list/'+filename+'.dat' #binary file for RTL use
    filename_dec = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath('__file__')))) + '/dnn-hlsims/network_models/wtbias_initdata/'+filename+'_DEC.dat' #write decimal values to file as well, for hlsims use
    f_bin = open(filename_bin,'wb')
    f_dec = open(filename_dec,'wb')
    width = frac_bits + int_bits + 1 #1 for sign bit
    x = np.random.normal(0,np.sqrt(2./(fi+fo)), numentries)
    x[x>2**int_bits-2**(-frac_bits)] = 2**int_bits-2**(-frac_bits) #positive limit
    x[x<-2**int_bits] = -2**int_bits #negative limit
    for i in range(len(x)):
        x_bin = format(int(2**(width+1) + x[i]*(2**frac_bits)), 'b')
        f_bin.write('{0}\n'.format(x_bin[-width:]))
        f_dec.write('{0}\n'.format(x[i]))
    f_bin.close()
    f_dec.close()

def convert2hex(filename='s136_frc21_int10'):
    filename_bin = os.path.dirname(os.path.dirname(os.path.realpath('__file__'))) + '/gaussian_list/'+filename+'.dat'
    filename_hex = os.path.dirname(os.path.dirname(os.path.realpath('__file__'))) + '/gaussian_list/'+filename+'_HEX.dat' #hex file for RTL use

    with open (filename_bin, 'rb') as f:
        flines = f.readlines()

    with open (filename_hex, 'wb') as f_hex:
        for i in range(len(flines)):
            line = flines[i].strip('\n')
            while len(line)%4 != 0:
                line = '0'+line #add 0s to get multiple of 4 bits
            f_hex_line = '' #Add new hex digits here
            for j in range(0, len(line), 4):
                f_hex_line += hex(int(line[j:j+4],2)).upper()[2:] #upper converts to capital, [2:] is to get rid of 0x at beginning
            f_hex.write('{0},'.format(f_hex_line)) #output has values separated by commas


########################## ONLY CHANGE THIS SECTION ###########################
fo = [8,8]
fi = [128,32]
int_bits = 2
frac_bits = 7
###############################################################################

#glorotnormal_init_generate(fi[0],fo[0],int_bits,frac_bits, filename='/s{0}_frc{1}_int{2}'.format(fi[0]+fo[0],frac_bits,int_bits))
#glorotnormal_init_generate(fi[1],fo[1],int_bits,frac_bits, filename='/s{0}_frc{1}_int{2}'.format(fi[1]+fo[1],frac_bits,int_bits))
convert2hex(filename='/s{0}_frc{1}_int{2}'.format(fi[0]+fo[0],frac_bits,int_bits))
convert2hex(filename='/s{0}_frc{1}_int{2}'.format(fi[1]+fo[1],frac_bits,int_bits))
