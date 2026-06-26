int modbusCrc16(List<int> data) {
  var crc = 0xffff;
  for (final byte in data) {
    crc ^= byte & 0xff;
    for (var i = 0; i < 8; i++) {
      if ((crc & 0x0001) != 0) {
        crc >>= 1;
        crc ^= 0xa001;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc & 0xffff;
}
