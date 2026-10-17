 










#ifndef DES_H
#define DES_H

 
#include <stddef.h>

 
#define DES_BLOCK_SIZE 8                

 
typedef unsigned char BYTE;             
typedef unsigned int  WORD;             

typedef enum {
	DES_ENCRYPT,
	DES_DECRYPT
} DES_MODE;

 
void des_key_setup(const BYTE key[], BYTE schedule[][6], DES_MODE mode);
void des_crypt(const BYTE in[], BYTE out[], const BYTE key[][6]);

void three_des_key_setup(const BYTE key[], BYTE schedule[][16][6], DES_MODE mode);
void three_des_crypt(const BYTE in[], BYTE out[], const BYTE key[][16][6]);

#endif   

