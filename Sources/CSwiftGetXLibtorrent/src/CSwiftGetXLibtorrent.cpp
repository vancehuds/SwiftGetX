#include "CSwiftGetXLibtorrent.h"

#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_flags.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>

#include <algorithm>
#include <cstring>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

struct SGXLibtorrentSession {
    lt::session session;
    std::unordered_map<int32_t, lt::torrent_handle> handles;
    int32_t next_handle_id = 1;
    std::string last_error;

    SGXLibtorrentSession()
        : session(make_params())
    {
    }

    static lt::session_params make_params()
    {
        lt::settings_pack settings;
        settings.set_bool(lt::settings_pack::enable_dht, true);
        settings.set_bool(lt::settings_pack::enable_lsd, true);
        settings.set_bool(lt::settings_pack::enable_upnp, true);
        settings.set_bool(lt::settings_pack::enable_natpmp, true);
        settings.set_int(lt::settings_pack::alert_mask, lt::alert_category::error | lt::alert_category::status);
        return lt::session_params(settings);
    }

    int32_t store(lt::torrent_handle handle)
    {
        int32_t id = next_handle_id++;
        handles[id] = handle;
        return id;
    }

    lt::torrent_handle *find(int32_t id)
    {
        auto it = handles.find(id);
        if (it == handles.end()) return nullptr;
        return &it->second;
    }

    void set_error(std::string message)
    {
        last_error = std::move(message);
    }
};

static void apply_file_selection(lt::add_torrent_params &params, const int32_t *selected, int32_t count)
{
    if (count < 0) return;
    if (selected == nullptr) {
        if (count == 0) params.flags |= lt::torrent_flags::default_dont_download;
        return;
    }
    if (count == 0) {
        params.flags |= lt::torrent_flags::default_dont_download;
        return;
    }
    params.flags |= lt::torrent_flags::default_dont_download;
    int32_t max_index = 0;
    for (int32_t i = 0; i < count; ++i) max_index = std::max(max_index, selected[i]);
    params.file_priorities.assign(static_cast<std::size_t>(max_index + 1), lt::dont_download);
    for (int32_t i = 0; i < count; ++i) {
        if (selected[i] >= 0) params.file_priorities[static_cast<std::size_t>(selected[i])] = lt::default_priority;
    }
}

SGXLibtorrentSession *sgx_libtorrent_session_create(void)
{
    try {
        return new SGXLibtorrentSession();
    } catch (...) {
        return nullptr;
    }
}

void sgx_libtorrent_session_destroy(SGXLibtorrentSession *session)
{
    delete session;
}

int32_t sgx_libtorrent_add_magnet(
    SGXLibtorrentSession *session,
    const char *magnet_uri,
    const char *save_path,
    const int32_t *selected_file_indexes,
    int32_t selected_file_count
)
{
    if (session == nullptr || magnet_uri == nullptr || save_path == nullptr) return -1;
    try {
        lt::error_code ec;
        lt::add_torrent_params params = lt::parse_magnet_uri(magnet_uri, ec);
        if (ec) {
            session->set_error(ec.message());
            return -1;
        }
        params.save_path = save_path;
        apply_file_selection(params, selected_file_indexes, selected_file_count);
        return session->store(session->session.add_torrent(params));
    } catch (std::exception const &error) {
        session->set_error(error.what());
        return -1;
    }
}

int32_t sgx_libtorrent_add_torrent_file(
    SGXLibtorrentSession *session,
    const char *torrent_file_path,
    const char *save_path,
    const int32_t *selected_file_indexes,
    int32_t selected_file_count
)
{
    if (session == nullptr || torrent_file_path == nullptr || save_path == nullptr) return -1;
    try {
        lt::add_torrent_params params;
        params.ti = std::make_shared<lt::torrent_info>(torrent_file_path);
        params.save_path = save_path;
        apply_file_selection(params, selected_file_indexes, selected_file_count);
        return session->store(session->session.add_torrent(params));
    } catch (std::exception const &error) {
        session->set_error(error.what());
        return -1;
    }
}

void sgx_libtorrent_pause(SGXLibtorrentSession *session, int32_t handle_id)
{
    if (auto *handle = session ? session->find(handle_id) : nullptr) handle->pause();
}

void sgx_libtorrent_resume(SGXLibtorrentSession *session, int32_t handle_id)
{
    if (auto *handle = session ? session->find(handle_id) : nullptr) handle->resume();
}

void sgx_libtorrent_remove(SGXLibtorrentSession *session, int32_t handle_id, int32_t delete_files)
{
    if (session == nullptr) return;
    auto *handle = session->find(handle_id);
    if (handle == nullptr) return;
    auto option = delete_files ? lt::session::delete_files : lt::session::delete_partfile;
    session->session.remove_torrent(*handle, option);
    session->handles.erase(handle_id);
}

void sgx_libtorrent_recheck(SGXLibtorrentSession *session, int32_t handle_id)
{
    if (auto *handle = session ? session->find(handle_id) : nullptr) handle->force_recheck();
}

void sgx_libtorrent_set_speed_limits(SGXLibtorrentSession *session, int32_t download_bytes_per_second, int32_t upload_bytes_per_second)
{
    if (session == nullptr) return;
    lt::settings_pack settings;
    settings.set_int(lt::settings_pack::download_rate_limit, download_bytes_per_second);
    settings.set_int(lt::settings_pack::upload_rate_limit, upload_bytes_per_second);
    session->session.apply_settings(settings);
}

void sgx_libtorrent_set_file_selection(SGXLibtorrentSession *session, int32_t handle_id, const int32_t *selected_file_indexes, int32_t selected_file_count)
{
    auto *handle = session ? session->find(handle_id) : nullptr;
    if (handle == nullptr) return;
    auto info = handle->torrent_file();
    if (!info) return;
    int file_count = info->num_files();
    for (int i = 0; i < file_count; ++i) handle->file_priority(lt::file_index_t(i), lt::dont_download);
    for (int32_t i = 0; i < selected_file_count; ++i) {
        if (selected_file_indexes[i] >= 0 && selected_file_indexes[i] < file_count) {
            handle->file_priority(lt::file_index_t(selected_file_indexes[i]), lt::default_priority);
        }
    }
}

int32_t sgx_libtorrent_get_status(SGXLibtorrentSession *session, int32_t handle_id, SGXTorrentStatus *status)
{
    auto *handle = session ? session->find(handle_id) : nullptr;
    if (handle == nullptr || status == nullptr) return 0;
    auto native = handle->status();
    status->state = static_cast<int32_t>(native.state);
    status->is_finished = native.is_finished ? 1 : 0;
    status->is_seeding = native.is_seeding ? 1 : 0;
    status->is_paused = (handle->flags() & lt::torrent_flags::paused) ? 1 : 0;
    status->has_metadata = native.state != lt::torrent_status::downloading_metadata ? 1 : 0;
    status->has_error = native.errc ? 1 : 0;
    status->total_wanted = native.total_wanted;
    status->total_wanted_done = native.total_wanted_done;
    status->download_rate = native.download_rate;
    status->upload_rate = native.upload_rate;
    status->num_peers = native.num_peers;
    status->progress = native.progress;
    status->distributed_copies = native.distributed_copies;
    status->share_ratio = native.all_time_download > 0
        ? static_cast<float>(native.all_time_upload) / static_cast<float>(native.all_time_download)
        : 0;
    return 1;
}

int32_t sgx_libtorrent_has_metadata(SGXLibtorrentSession *session, int32_t handle_id)
{
    auto *handle = session ? session->find(handle_id) : nullptr;
    if (handle == nullptr) return 0;
    return handle->torrent_file() ? 1 : 0;
}

int32_t sgx_libtorrent_copy_files(SGXLibtorrentSession *session, int32_t handle_id, SGXTorrentFile *files, int32_t max_files)
{
    auto *handle = session ? session->find(handle_id) : nullptr;
    if (handle == nullptr || files == nullptr || max_files <= 0) return 0;
    auto info = handle->torrent_file();
    if (!info) return 0;

    int count = std::min(info->num_files(), max_files);
    auto priorities = handle->get_file_priorities();
    auto progress = handle->file_progress();
    auto const &storage = info->files();
    for (int i = 0; i < count; ++i) {
        auto file_index = lt::file_index_t(i);
        std::string path = storage.file_path(file_index);
        char *path_copy = new char[path.size() + 1];
        std::memcpy(path_copy, path.c_str(), path.size() + 1);
        files[i].index = i;
        files[i].size = storage.file_size(file_index);
        files[i].priority = i < static_cast<int>(priorities.size())
            ? static_cast<int32_t>(static_cast<std::uint8_t>(priorities[static_cast<std::size_t>(i)]))
            : 1;
        files[i].progress = i < static_cast<int>(progress.size()) && files[i].size > 0
            ? static_cast<float>(progress[static_cast<std::size_t>(i)]) / static_cast<float>(files[i].size)
            : 0;
        files[i].path = path_copy;
    }
    return count;
}

void sgx_libtorrent_free_file_paths(SGXTorrentFile *files, int32_t file_count)
{
    if (files == nullptr) return;
    for (int32_t i = 0; i < file_count; ++i) {
        delete[] files[i].path;
        files[i].path = nullptr;
    }
}

const char *sgx_libtorrent_last_error(SGXLibtorrentSession *session)
{
    if (session == nullptr) return "No libtorrent session";
    return session->last_error.c_str();
}
