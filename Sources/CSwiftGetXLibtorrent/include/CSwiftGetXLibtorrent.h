#ifndef CSWIFTGETX_LIBTORRENT_H
#define CSWIFTGETX_LIBTORRENT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SGXLibtorrentSession SGXLibtorrentSession;

typedef struct SGXTorrentStatus {
    int32_t state;
    int64_t total_wanted;
    int64_t total_wanted_done;
    int64_t download_rate;
    int64_t upload_rate;
    int32_t num_peers;
    float progress;
    float distributed_copies;
    float share_ratio;
} SGXTorrentStatus;

typedef struct SGXTorrentFile {
    int32_t index;
    int64_t size;
    int32_t priority;
    float progress;
    const char *path;
} SGXTorrentFile;

SGXLibtorrentSession *sgx_libtorrent_session_create(void);
void sgx_libtorrent_session_destroy(SGXLibtorrentSession *session);

int32_t sgx_libtorrent_add_magnet(
    SGXLibtorrentSession *session,
    const char *magnet_uri,
    const char *save_path,
    const int32_t *selected_file_indexes,
    int32_t selected_file_count
);

int32_t sgx_libtorrent_add_torrent_file(
    SGXLibtorrentSession *session,
    const char *torrent_file_path,
    const char *save_path,
    const int32_t *selected_file_indexes,
    int32_t selected_file_count
);

void sgx_libtorrent_pause(SGXLibtorrentSession *session, int32_t handle_id);
void sgx_libtorrent_resume(SGXLibtorrentSession *session, int32_t handle_id);
void sgx_libtorrent_remove(SGXLibtorrentSession *session, int32_t handle_id, int32_t delete_files);
void sgx_libtorrent_recheck(SGXLibtorrentSession *session, int32_t handle_id);
void sgx_libtorrent_set_speed_limits(SGXLibtorrentSession *session, int32_t download_bytes_per_second, int32_t upload_bytes_per_second);
void sgx_libtorrent_set_file_selection(SGXLibtorrentSession *session, int32_t handle_id, const int32_t *selected_file_indexes, int32_t selected_file_count);

int32_t sgx_libtorrent_get_status(SGXLibtorrentSession *session, int32_t handle_id, SGXTorrentStatus *status);
int32_t sgx_libtorrent_copy_files(SGXLibtorrentSession *session, int32_t handle_id, SGXTorrentFile *files, int32_t max_files);
void sgx_libtorrent_free_file_paths(SGXTorrentFile *files, int32_t file_count);
const char *sgx_libtorrent_last_error(SGXLibtorrentSession *session);

#ifdef __cplusplus
}
#endif

#endif
