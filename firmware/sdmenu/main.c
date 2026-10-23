#include <stdint.h>
#include <string.h>

void microwait(int us);
int sd_init(void);
int sd_readsector(uint32_t start_block, uint8_t *buffer, uint32_t sector_count);
int sd_writesector(uint32_t start_block, uint8_t *buffer, uint32_t sector_count);

#include "io.h"
#include <fat_io_lib/fat_filelib.h>

#define MAX_FILES 64
#define NAME_LEN  FATFS_MAX_LONG_FILENAME
#define LIST_ROWS 15
#define DISP_COLS 38

static char names[MAX_FILES][NAME_LEN];
static uint8_t entry_dir[MAX_FILES];
static int file_count;
static int selected;
static int scroll;
static char cwd[FATFS_MAX_LONG_FILENAME];

static void delay_ms(int ms)
{
  for (int i = 0; i < ms; i++)
    microwait(1000);
}

static int ends_with_sms(const char *name)
{
  int len = (int)strlen(name);
  if (len < 4)
    return 0;
  const char *ext = name + len - 4;
  return ext[0] == '.' &&
         ((ext[1] == 's' || ext[1] == 'S') &&
          (ext[2] == 'm' || ext[2] == 'M') &&
          (ext[3] == 's' || ext[3] == 'S'));
}

/* sig is the 18 bytes at file offset 0x7FE6 (checksum through "TMR SEGA"). */
static int mapper_codemasters(const uint8_t *sig, uint32_t len)
{
  if (len <= 0x7fff)
    return 0;
  uint16_t word = (uint16_t)sig[0] | ((uint16_t)sig[1] << 8);
  uint16_t comp = (uint16_t)sig[2] | ((uint16_t)sig[3] << 8);
  if (word == 0 || ((word + comp) & 0xffff) != 0)
    return 0;
  for (int i = 0; i < 6; i++)
    if (sig[4 + i] != 0)
      return 0;
  if (memcmp(sig + 10, "TMR SEGA", 8) != 0)
    return 0;
  return 1;
}

static int is_dot_dir(const char *name)
{
  return name[0] == '.' &&
         (name[1] == '\0' || (name[1] == '.' && name[2] == '\0'));
}

static char display_char(unsigned char uc)
{
  return (uc >= 0x20 && uc <= 0x7e) ? (char)uc : '?';
}

static void overlay_clear(void)
{
  for (uint8_t row = 0; row < LIST_ROWS + 1; row++)
    for (uint8_t col = 0; col < 40; col++)
      overlay_put(row, col, ' ');
}

static void overlay_msg(const char *msg)
{
  overlay_clear();
  overlay_set_sel(0xFF);
  for (uint8_t col = 0; msg[col] && col < DISP_COLS; col++)
    overlay_put(0, col, msg[col]);
}

static void show_loading(const char *name)
{
  char msg[DISP_COLS + 1];
  const char *prefix = "Loading... ";
  int i = 0;
  while (prefix[i] && i < DISP_COLS) {
    msg[i] = prefix[i];
    i++;
  }
  for (int k = 0; name[k] && i < DISP_COLS; k++)
    msg[i++] = display_char((unsigned char)name[k]);
  msg[i] = '\0';
  overlay_msg(msg);
}

static void draw_path(void)
{
  int len = (int)strlen(cwd);
  if (len > DISP_COLS) {
    int start = len - (DISP_COLS - 1);
    overlay_put(0, 0, '<');
    for (int col = 1; col < DISP_COLS; col++)
      overlay_put(0, (uint8_t)col, display_char((unsigned char)cwd[start + col - 1]));
    return;
  }
  for (int col = 0; col < len; col++)
    overlay_put(0, (uint8_t)col, display_char((unsigned char)cwd[col]));
}

static void draw_entry(uint8_t row, int idx)
{
  const char *name = names[idx];
  int limit = entry_dir[idx] ? DISP_COLS - 1 : DISP_COLS;
  int col = 0;
  for (; col < limit && name[col]; col++)
    overlay_put(row, (uint8_t)col, display_char((unsigned char)name[col]));
  if (entry_dir[idx])
    overlay_put(row, (uint8_t)col, '/');
}

static void draw_list(void)
{
  overlay_clear();
  draw_path();
  overlay_set_sel((uint8_t)(selected - scroll + 1));
  for (int i = 0; i < LIST_ROWS; i++) {
    int idx = scroll + i;
    if (idx >= file_count)
      break;
    draw_entry((uint8_t)(i + 1), idx);
  }
}

static uint32_t prev_buttons;

static uint32_t button_edges(void)
{
  uint32_t now = IO_IN(IO_BUTTONS);
  uint32_t edge = now & ~prev_buttons;
  prev_buttons = now;
  return edge;
}

static void copy_name(int idx, const char *name)
{
  strncpy(names[idx], name, NAME_LEN - 1);
  names[idx][NAME_LEN - 1] = '\0';
}

static int fold_char(unsigned char c)
{
  if (c >= 'A' && c <= 'Z')
    return c + ('a' - 'A');
  return c;
}

/* Directories before files, then case-insensitive name order. */
static int entry_before(const char *a, int a_dir, const char *b, int b_dir)
{
  if (a_dir != b_dir)
    return a_dir > b_dir;
  while (*a && *b) {
    int ca = fold_char((unsigned char)*a++);
    int cb = fold_char((unsigned char)*b++);
    if (ca != cb)
      return ca < cb;
  }
  return *a == '\0' && *b != '\0';
}

static void sort_entries(int start)
{
  for (int i = start + 1; i < file_count; i++) {
    char tmp[NAME_LEN];
    uint8_t tmp_dir = entry_dir[i];
    memcpy(tmp, names[i], NAME_LEN);
    int j = i;
    while (j > start && entry_before(tmp, tmp_dir, names[j - 1], entry_dir[j - 1])) {
      memcpy(names[j], names[j - 1], NAME_LEN);
      entry_dir[j] = entry_dir[j - 1];
      j--;
    }
    memcpy(names[j], tmp, NAME_LEN);
    entry_dir[j] = tmp_dir;
  }
}

/* List directories and .sms files. ".." is inserted first when not at root. */
static int scan_dir(const char *path)
{
  int root = path[0] == '/' && path[1] == '\0';
  FL_DIR d;
  struct fs_dir_ent ent;

  if (!fl_opendir(path, &d))
    return -1;
  file_count = 0;
  if (!root && file_count < MAX_FILES) {
    copy_name(0, "..");
    entry_dir[0] = 1;
    file_count = 1;
  }
  while (fl_readdir(&d, &ent) == 0 && file_count < MAX_FILES) {
    if (ent.is_dir) {
      if (is_dot_dir(ent.filename))
        continue;
      copy_name(file_count, ent.filename);
      entry_dir[file_count] = 1;
      file_count++;
    } else if (ends_with_sms(ent.filename)) {
      copy_name(file_count, ent.filename);
      entry_dir[file_count] = 0;
      file_count++;
    }
  }
  fl_closedir(&d);
  sort_entries(root ? 0 : 1);
  return 0;
}

static int open_listed_dir(const char *path)
{
  if (scan_dir(path))
    return -1;
  strncpy(cwd, path, sizeof(cwd) - 1);
  cwd[sizeof(cwd) - 1] = '\0';
  selected = 0;
  scroll = 0;
  if (file_count > 0)
    draw_list();
  return 0;
}

static int join_path(char *out, int outlen, const char *dir, const char *name)
{
  int n = 0;

  if (dir[0] == '/' && dir[1] == '\0') {
    if (outlen < 2)
      return -1;
    out[n++] = '/';
  } else {
    while (dir[n] && n < outlen - 1) {
      out[n] = dir[n];
      n++;
    }
    if (dir[n])
      return -1;
    if (n + 1 >= outlen)
      return -1;
    out[n++] = '/';
  }
  for (int i = 0; name[i]; i++) {
    if (n + 1 >= outlen)
      return -1;
    out[n++] = name[i];
  }
  out[n] = '\0';
  return 0;
}

static void parent_of(const char *dir, char *out, int outlen)
{
  int n = 0;
  while (dir[n] && n < outlen - 1) {
    out[n] = dir[n];
    n++;
  }
  out[n] = '\0';
  if (n <= 1) {
    out[0] = '/';
    out[1] = '\0';
    return;
  }
  if (out[n - 1] == '/')
    out[--n] = '\0';
  while (n > 1 && out[n - 1] != '/')
    n--;
  if (n <= 1) {
    out[0] = '/';
    out[1] = '\0';
  } else {
    out[n - 1] = '\0';
  }
}

static int load_rom(const char *path)
{
  void *fh = fl_fopen(path, "r");
  if (!fh)
    return -1;
  uint32_t len = ((FL_FILE *)fh)->filelength;
  if (len == 0 || len > (4u * 1024u * 1024u)) {
    fl_fclose(fh);
    return -1;
  }

  const char *base = strrchr(path, '/');
  show_loading(base ? base + 1 : path);
  sdram_set_length(len);

  uint8_t sector[512];
  uint8_t sig[18] = {0};
  uint32_t got = 0;
  int mapper = 0;

  while (got < len) {
    uint32_t chunk = len - got;
    if (chunk > 512)
      chunk = 512;
    if (fl_fread(sector, 1, chunk, fh) != chunk) {
      fl_fclose(fh);
      return -1;
    }
    for (uint32_t i = 0; i < chunk; i++) {
      uint32_t off = got + i;
      if (off >= 0x7fe6 && off < 0x7fe6 + sizeof(sig))
        sig[off - 0x7fe6] = sector[i];
      sdram_write_byte(sector[i]);
    }
    got += chunk;
  }
  fl_fclose(fh);
  mapper = mapper_codemasters(sig, len);
  sdram_set_mapper(mapper);
  sdram_finalize();
  return 0;
}

int filesystem_init(void)
{
  if (sd_init())
    return -1;
  fl_init();
  if (fl_attach_media((fn_diskio_read)sd_readsector,
                      (fn_diskio_write)sd_writesector) != FAT_INIT_OK)
    return -1;
  return 0;
}

int main(void)
{
  prev_buttons = IO_IN(IO_BUTTONS);
  overlay_msg("SD init...");
  if (filesystem_init()) {
    overlay_msg("No SD / FAT");
    while (1)
      delay_ms(50);
  }

  if (open_listed_dir("/") || file_count == 0) {
    overlay_msg("No .sms files");
    while (1)
      delay_ms(100);
  }

  while (1) {
    uint32_t edge = button_edges();
    if (edge & (BTN_UP | BTN_PAD_U)) {
      if (selected > 0) {
        selected--;
        if (selected < scroll)
          scroll = selected;
        draw_list();
      }
    }
    if (edge & (BTN_DOWN | BTN_PAD_D)) {
      if (selected + 1 < file_count) {
        selected++;
        if (selected >= scroll + LIST_ROWS)
          scroll = selected - LIST_ROWS + 1;
        draw_list();
      }
    }
    if (edge & (BTN_FIRE | BTN_PAD_A)) {
      if (entry_dir[selected]) {
        char next[FATFS_MAX_LONG_FILENAME];
        int bad = 0;
        if (names[selected][0] == '.' && names[selected][1] == '.' &&
            names[selected][2] == '\0')
          parent_of(cwd, next, sizeof(next));
        else
          bad = join_path(next, sizeof(next), cwd, names[selected]);
        if (bad || open_listed_dir(next)) {
          overlay_msg(bad ? "Path too long" : "Can't open");
          delay_ms(700);
          draw_list();
        }
      } else {
        char path[FATFS_MAX_LONG_FILENAME];
        if (join_path(path, sizeof(path), cwd, names[selected]) ||
            load_rom(path) != 0) {
          overlay_msg("Load failed");
          delay_ms(700);
          draw_list();
        } else {
          while (1)
            ;
        }
      }
    }
    delay_ms(30);
  }
  return 0;
}
