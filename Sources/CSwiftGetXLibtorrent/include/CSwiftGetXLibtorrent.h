#ifndef CSWIFTGETX_LIBTORRENT_H
#define CSWIFTGETX_LIBTORRENT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SGXLibtorrentSession SGXLibtorrentSession;

typedef struct SGXTorrentStatus {
    int32_t state;
    int32_t is_finished;
    int32_t is_seeding;
    int32_t is_paused;
    int32_t has_metadata;
    int32_t has_error;
    int32_t is_sequential_download;
    int32_t needs_resume_data_save;
    int64_t total_wanted;
    int64_t total_wanted_done;
    int64_t download_rate;
    int64_t upload_rate;
    int32_t num_peers;
    int32_t num_connections;
    int32_t num_uploads;
    int32_t listen_port;
    int32_t dht_nodes;
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

typedef struct SGXTorrentTracker {
    const char *url;
    const char *status;
    const char *last_announce;
    const char *next_announce;
    const char *error_message;
    int32_t tier;
    int32_t seed_count;
    int32_t leecher_count;
    int32_t downloaded_count;
} SGXTorrentTracker;

typedef struct SGXTorrentPeer {
    const char *address;
    const char *client;
    const char *direction;
    const char *flags;
    float progress;
    int64_t download_rate;
    int64_t upload_rate;
} SGXTorrentPeer;

SGXLibtorrentSession *sgx_libtorrent_session_create(void);
void sgx_libtorrent_session_destroy(SGXLibtorrentSession *session);
void sgx_libtorrent_apply_runtime_options(
    SGXLibtorrentSession *session,
    int32_t enable_dht,
    int32_t enable_lsd,
    int32_t max_connections,
    int32_t max_upload_slots
);

int32_t sgx_libtorrent_add_magnet(
    SGXLibtorrentSession *session,
    const char *magnet_uri,
    const char *save_path,
    const int32_t *selected_file_indexes,
    int32_t selected_file_count
);

int32_t sgx_libtorrent_add_magnet_with_options(
    SGXLibtorrentSession *session,
    const char *magnet_uri,
    const char *save_path,
    const int32_t *selected_file_indexes,
    int32_t selected_file_count,
    const int32_t *file_priority_indexes,
    const int32_t *file_priority_values,
    int32_t file_priority_count,
    const char *resume_data_path,
    int32_t sequential_download,
    int32_t enable_dht,
    int32_t enable_pex,
    int32_t enable_lsd
);

int32_t sgx_libtorrent_add_torrent_file(
    SGXLibtorrentSession *session,
    const char *torrent_file_path,
    const char *save_path,
    const int32_t *selected_file_indexes,
    int32_t selected_file_count
);

int32_t sgx_libtorrent_add_torrent_file_with_options(
    SGXLibtorrentSession *session,
    const char *torrent_file_path,
    const char *save_path,
    const int32_t *selected_file_indexes,
    int32_t selected_file_count,
    const int32_t *file_priority_indexes,
    const int32_t *file_priority_values,
    int32_t file_priority_count,
    const char *resume_data_path,
    int32_t sequential_download,
    int32_t enable_dht,
    int32_t enable_pex,
    int32_t enable_lsd
);

void sgx_libtorrent_pause(SGXLibtorrentSession *session, int32_t handle_id);
void sgx_libtorrent_resume(SGXLibtorrentSession *session, int32_t handle_id);
void sgx_libtorrent_remove(SGXLibtorrentSession *session, int32_t handle_id, int32_t delete_files);
void sgx_libtorrent_recheck(SGXLibtorrentSession *session, int32_t handle_id);
void sgx_libtorrent_set_speed_limits(SGXLibtorrentSession *session, int32_t download_bytes_per_second, int32_t upload_bytes_per_second);
void sgx_libtorrent_set_file_selection(SGXLibtorrentSession *session, int32_t handle_id, const int32_t *selected_file_indexes, int32_t selected_file_count);
void sgx_libtorrent_set_file_priority(SGXLibtorrentSession *session, int32_t handle_id, int32_t file_index, int32_t priority);
void sgx_libtorrent_set_sequential_download(SGXLibtorrentSession *session, int32_t handle_id, int32_t enabled);
void sgx_libtorrent_set_torrent_runtime_options(
    SGXLibtorrentSession *session,
    int32_t handle_id,
    int32_t enable_dht,
    int32_t enable_pex,
    int32_t enable_lsd,
    int32_t sequential_download
);
void sgx_libtorrent_add_tracker(SGXLibtorrentSession *session, int32_t handle_id, const char *url);
void sgx_libtorrent_remove_tracker(SGXLibtorrentSession *session, int32_t handle_id, const char *url);
void sgx_libtorrent_force_reannounce(SGXLibtorrentSession *session, int32_t handle_id);
int32_t sgx_libtorrent_save_resume_data(SGXLibtorrentSession *session, int32_t handle_id, const char *resume_data_path);

int32_t sgx_libtorrent_get_status(SGXLibtorrentSession *session, int32_t handle_id, SGXTorrentStatus *status);
int32_t sgx_libtorrent_has_metadata(SGXLibtorrentSession *session, int32_t handle_id);
int32_t sgx_libtorrent_copy_files(SGXLibtorrentSession *session, int32_t handle_id, SGXTorrentFile *files, int32_t max_files);
void sgx_libtorrent_free_file_paths(SGXTorrentFile *files, int32_t file_count);
int32_t sgx_libtorrent_copy_trackers(SGXLibtorrentSession *session, int32_t handle_id, SGXTorrentTracker *trackers, int32_t max_trackers);
void sgx_libtorrent_free_trackers(SGXTorrentTracker *trackers, int32_t tracker_count);
int32_t sgx_libtorrent_copy_peers(SGXLibtorrentSession *session, int32_t handle_id, SGXTorrentPeer *peers, int32_t max_peers);
void sgx_libtorrent_free_peers(SGXTorrentPeer *peers, int32_t peer_count);
const char *sgx_libtorrent_last_error(SGXLibtorrentSession *session);

#ifdef __cplusplus
}
#endif

#endif
