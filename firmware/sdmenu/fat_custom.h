/* 96 covers a long ROM name plus a short directory. 260 made the
   menu image too big for a 32 KiB block RAM on the ECP5-25. */
#define FATFS_MAX_LONG_FILENAME 96
#define FATFS_INC_WRITE_SUPPORT 0
#define FATFS_DIR_LIST_SUPPORT 1
#define FATFS_INC_LFN_SUPPORT 1
#define FATFS_INC_TIME_DATE_SUPPORT 0
#define FATFS_INC_FORMAT_SUPPORT 0
#define FATFS_MAX_OPEN_FILES 2
#define FAT_PRINTF(a)
