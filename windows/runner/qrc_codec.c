#include <stdint.h>
#include "des.h"

 
static const BYTE qrc_key[] = "!@#)(*$%123ZXC!@!@#)(NHL";

__declspec(dllexport) int32_t md3_qrc_decode(const uint8_t* input,
                                           uint8_t* output, int32_t length) {
  if (!input || !output || length <= 0 || length > 524288 || length % 8 != 0 ||
      sizeof(qrc_key) - 1 != 24) return -1;
  BYTE schedule[3][16][6];
  three_des_key_setup(qrc_key, schedule, DES_DECRYPT);
  for (int32_t index = 0; index < length; index += 8)
    three_des_crypt(input + index, output + index, schedule);
  return 0;
}
