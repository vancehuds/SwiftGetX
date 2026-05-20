#include "CSwiftGetXLibtorrent.h"

#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/alert.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/announce_entry.hpp>
#include <libtorrent/bencode.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/peer_info.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/session_stats.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_flags.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/write_resume_data.hpp>

#include <algorithm>
#include <chrono>
#include <cstring>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

struct SGXLibtorrentSession {
    lt::session session;
    std::unordered_map<int32_t, lt::torrent_handle> handles;
    int32_t next_handle_id = 1;
    int32_t last_dht_nodes = 0;
    int dht_nodes_metric_index = -2;
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

    int dht_nodes_metric()
    {
        if (dht_nodes_metric_index == -2) {
            dht_nodes_metric_index = lt::find_metric_idx("dht.dht_nodes");
        }
        return dht_nodes_metric_index;
    }

    void refresh_session_stats()
    {
        try {
            std::vector<lt::alert *> alerts;
            session.pop_alerts(&alerts);
            int const metric = dht_nodes_metric();
            for (lt::alert *alert : alerts) {
                auto const *stats = lt::alert_cast<lt::session_stats_alert>(alert);
                if (stats == nullptr || metric < 0) continue;
                auto counters = stats->counters();
                auto const index = static_cast<std::size_t>(metric);
                if (index < counters.size()) {
                    last_dht_nodes = static_cast<int32_t>(std::max<std::int64_t>(0, counters[index]));
                }
            }
            session.post_session_stats();
        } catch (...) {
        }
    }
};

static char *copy_c_string(std::string const &value)
{
    char *copy = new char[value.size() + 1];
    std::memcpy(copy, value.c_str(), value.size() + 1);
    return copy;
}

static int clamp_priority(int value)
{
    return std::max(0, std::min(value, 7));
}

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

static void apply_file_priorities(
    lt::add_torrent_params &params,
    const int32_t *indexes,
    const int32_t *priorities,
    int32_t count
)
{
    if (indexes == nullptr || priorities == nullptr || count <= 0) return;
    int32_t max_index = 0;
    for (int32_t i = 0; i < count; ++i) {
        if (indexes[i] >= 0) max_index = std::max(max_index, indexes[i]);
    }
    if (params.file_priorities.size() < static_cast<std::size_t>(max_index + 1)) {
        params.file_priorities.resize(static_cast<std::size_t>(max_index + 1), lt::default_priority);
    }
    for (int32_t i = 0; i < count; ++i) {
        if (indexes[i] >= 0) {
            int priority = clamp_priority(priorities[i]);
            params.file_priorities[static_cast<std::size_t>(indexes[i])] = lt::download_priority_t(priority);
        }
    }
}

static bool load_resume_data(const char *path, lt::add_torrent_params &params, std::string &error)
{
    if (path == nullptr || path[0] == '\0') return false;
    std::ifstream input(path, std::ios::binary);
    if (!input.good()) return false;
    std::vector<char> buffer((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    if (buffer.empty()) {
        error = "Resume data is empty";
        return false;
    }

    lt::error_code ec;
    params = lt::read_resume_data(lt::span<char const>(buffer.data(), buffer.size()), ec);
    if (ec) {
        error = ec.message();
        return false;
    }
    return true;
}

static void apply_common_options(
    lt::add_torrent_params &params,
    const char *save_path,
    const int32_t *selected_file_indexes,
    int32_t selected_file_count,
    const int32_t *file_priority_indexes,
    const int32_t *file_priority_values,
    int32_t file_priority_count,
    int32_t sequential_download,
    int32_t enable_dht,
    int32_t enable_pex,
    int32_t enable_lsd
)
{
    params.save_path = save_path;
    if (sequential_download) params.flags |= lt::torrent_flags::sequential_download;
    else params.flags &= ~lt::torrent_flags::sequential_download;
    if (enable_dht) params.flags &= ~lt::torrent_flags::disable_dht;
    else params.flags |= lt::torrent_flags::disable_dht;
    if (enable_pex) params.flags &= ~lt::torrent_flags::disable_pex;
    else params.flags |= lt::torrent_flags::disable_pex;
    if (enable_lsd) params.flags &= ~lt::torrent_flags::disable_lsd;
    else params.flags |= lt::torrent_flags::disable_lsd;
    apply_file_selection(params, selected_file_indexes, selected_file_count);
    apply_file_priorities(params, file_priority_indexes, file_priority_values, file_priority_count);
}

static void apply_torrent_runtime_options(
    lt::torrent_handle &handle,
    int32_t enable_dht,
    int32_t enable_pex,
    int32_t enable_lsd,
    int32_t sequential_download
)
{
    if (enable_dht) handle.unset_flags(lt::torrent_flags::disable_dht);
    else handle.set_flags(lt::torrent_flags::disable_dht);
    if (enable_pex) handle.unset_flags(lt::torrent_flags::disable_pex);
    else handle.set_flags(lt::torrent_flags::disable_pex);
    if (enable_lsd) handle.unset_flags(lt::torrent_flags::disable_lsd);
    else handle.set_flags(lt::torrent_flags::disable_lsd);
    if (sequential_download) handle.set_flags(lt::torrent_flags::sequential_download);
    else handle.unset_flags(lt::torrent_flags::sequential_download);
}

static std::string time_label(lt::time_point32 value)
{
    if (value == lt::time_point32::min()) return "";
    auto seconds = std::chrono::duration_cast<std::chrono::seconds>(value.time_since_epoch()).count();
    return std::to_string(seconds);
}

static std::string tracker_status(lt::announce_entry const &tracker)
{
    if (tracker.endpoints.empty()) return tracker.verified ? "ready" : "waiting";
    auto const &endpoint = tracker.endpoints.front();
    auto const &infohash = endpoint.info_hashes[lt::protocol_version::V1];
    if (infohash.updating) return "updating";
    if (infohash.last_error) return "error";
    if (infohash.fails > 0) return "retrying";
    return tracker.verified ? "working" : "waiting";
}

static std::string peer_flags_label(lt::peer_info const &peer)
{
    std::vector<std::string> labels;
    if (peer.flags & lt::peer_info::seed) labels.push_back("seed");
    if (peer.flags & lt::peer_info::utp_socket) labels.push_back("utp");
    if (peer.flags & lt::peer_info::ssl_socket) labels.push_back("ssl");
    if (peer.flags & lt::peer_info::remote_choked) labels.push_back("choked");
    if (peer.flags & lt::peer_info::interesting) labels.push_back("interesting");
    if (peer.source & lt::peer_info::tracker) labels.push_back("tracker");
    if (peer.source & lt::peer_info::dht) labels.push_back("dht");
    if (peer.source & lt::peer_info::pex) labels.push_back("pex");
    if (peer.source & lt::peer_info::lsd) labels.push_back("lsd");
    std::ostringstream stream;
    for (std::size_t i = 0; i < labels.size(); ++i) {
        if (i > 0) stream << ", ";
        stream << labels[i];
    }
    return stream.str();
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

void sgx_libtorrent_apply_runtime_options(
    SGXLibtorrentSession *session,
    int32_t enable_dht,
    int32_t enable_lsd,
    int32_t max_connections,
    int32_t max_upload_slots
)
{
    if (session == nullptr) return;
    lt::settings_pack settings;
    settings.set_bool(lt::settings_pack::enable_dht, enable_dht != 0);
    settings.set_bool(lt::settings_pack::enable_lsd, enable_lsd != 0);
    settings.set_int(lt::settings_pack::connections_limit, std::max(2, max_connections));
    settings.set_int(lt::settings_pack::unchoke_slots_limit, max_upload_slots);
    session->session.apply_settings(settings);
}

int32_t sgx_libtorrent_add_magnet(
    SGXLibtorrentSession *session,
    const char *magnet_uri,
    const char *save_path,
    const int32_t *selected_file_indexes,
    int32_t selected_file_count
)
{
    return sgx_libtorrent_add_magnet_with_options(
        session,
        magnet_uri,
        save_path,
        selected_file_indexes,
        selected_file_count,
        nullptr,
        nullptr,
        0,
        nullptr,
        0,
        1,
        1,
        1
    );
}

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
)
{
    if (session == nullptr || magnet_uri == nullptr || save_path == nullptr) return -1;
    try {
        lt::error_code ec;
        lt::add_torrent_params params;
        std::string resume_error;
        bool loaded_resume = load_resume_data(resume_data_path, params, resume_error);
        if (!loaded_resume && !resume_error.empty()) {
            session->set_error("Failed to load resume data: " + resume_error);
        }
        if (!loaded_resume) {
            params = lt::parse_magnet_uri(magnet_uri, ec);
        }
        if (ec) {
            session->set_error(ec.message());
            return -1;
        }
        apply_common_options(
            params,
            save_path,
            selected_file_indexes,
            selected_file_count,
            file_priority_indexes,
            file_priority_values,
            file_priority_count,
            sequential_download,
            enable_dht,
            enable_pex,
            enable_lsd
        );
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
    return sgx_libtorrent_add_torrent_file_with_options(
        session,
        torrent_file_path,
        save_path,
        selected_file_indexes,
        selected_file_count,
        nullptr,
        nullptr,
        0,
        nullptr,
        0,
        1,
        1,
        1
    );
}

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
)
{
    if (session == nullptr || torrent_file_path == nullptr || save_path == nullptr) return -1;
    try {
        lt::add_torrent_params params;
        std::string resume_error;
        bool loaded_resume = load_resume_data(resume_data_path, params, resume_error);
        if (!loaded_resume && !resume_error.empty()) {
            session->set_error("Failed to load resume data: " + resume_error);
        }
        if (!loaded_resume) {
            params.ti = std::make_shared<lt::torrent_info>(torrent_file_path);
        } else if (!params.ti) {
            params.ti = std::make_shared<lt::torrent_info>(torrent_file_path);
        }
        apply_common_options(
            params,
            save_path,
            selected_file_indexes,
            selected_file_count,
            file_priority_indexes,
            file_priority_values,
            file_priority_count,
            sequential_download,
            enable_dht,
            enable_pex,
            enable_lsd
        );
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

void sgx_libtorrent_set_file_priority(SGXLibtorrentSession *session, int32_t handle_id, int32_t file_index, int32_t priority)
{
    auto *handle = session ? session->find(handle_id) : nullptr;
    if (handle == nullptr || file_index < 0) return;
    auto info = handle->torrent_file();
    if (!info || file_index >= info->num_files()) return;
    handle->file_priority(lt::file_index_t(file_index), lt::download_priority_t(clamp_priority(priority)));
}

void sgx_libtorrent_set_sequential_download(SGXLibtorrentSession *session, int32_t handle_id, int32_t enabled)
{
    auto *handle = session ? session->find(handle_id) : nullptr;
    if (handle == nullptr) return;
    if (enabled) handle->set_flags(lt::torrent_flags::sequential_download);
    else handle->unset_flags(lt::torrent_flags::sequential_download);
}

void sgx_libtorrent_set_torrent_runtime_options(
    SGXLibtorrentSession *session,
    int32_t handle_id,
    int32_t enable_dht,
    int32_t enable_pex,
    int32_t enable_lsd,
    int32_t sequential_download
)
{
    auto *handle = session ? session->find(handle_id) : nullptr;
    if (handle == nullptr) return;
    apply_torrent_runtime_options(
        *handle,
        enable_dht,
        enable_pex,
        enable_lsd,
        sequential_download
    );
}

void sgx_libtorrent_add_tracker(SGXLibtorrentSession *session, int32_t handle_id, const char *url)
{
    auto *handle = session ? session->find(handle_id) : nullptr;
    if (handle == nullptr || url == nullptr || url[0] == '\0') return;
    handle->add_tracker(lt::announce_entry(url));
}

void sgx_libtorrent_remove_tracker(SGXLibtorrentSession *session, int32_t handle_id, const char *url)
{
    auto *handle = session ? session->find(handle_id) : nullptr;
    if (handle == nullptr || url == nullptr) return;
    auto trackers = handle->trackers();
    trackers.erase(
        std::remove_if(trackers.begin(), trackers.end(), [url](lt::announce_entry const &entry) {
            return entry.url == url;
        }),
        trackers.end()
    );
    handle->replace_trackers(trackers);
}

void sgx_libtorrent_force_reannounce(SGXLibtorrentSession *session, int32_t handle_id)
{
    auto *handle = session ? session->find(handle_id) : nullptr;
    if (handle == nullptr) return;
    handle->force_reannounce();
}

int32_t sgx_libtorrent_save_resume_data(SGXLibtorrentSession *session, int32_t handle_id, const char *resume_data_path)
{
    auto *handle = session ? session->find(handle_id) : nullptr;
    if (handle == nullptr || resume_data_path == nullptr || resume_data_path[0] == '\0') return 0;
    try {
        lt::add_torrent_params params = handle->get_resume_data();
        std::vector<char> data = lt::write_resume_data_buf(params);
        std::ofstream output(resume_data_path, std::ios::binary | std::ios::trunc);
        output.write(data.data(), static_cast<std::streamsize>(data.size()));
        if (!output.good()) {
            session->set_error("Failed to write resume data");
            return 0;
        }
        return 1;
    } catch (std::exception const &error) {
        session->set_error(error.what());
        return 0;
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
    status->has_metadata = handle->torrent_file() ? 1 : 0;
    status->has_error = native.errc ? 1 : 0;
    if (native.errc) {
        session->set_error(native.errc.message());
    }
    status->is_sequential_download = (handle->flags() & lt::torrent_flags::sequential_download) ? 1 : 0;
    status->needs_resume_data_save = handle->need_save_resume_data() ? 1 : 0;
    status->total_wanted = native.total_wanted;
    status->total_wanted_done = native.total_wanted_done;
    status->download_rate = native.download_rate;
    status->upload_rate = native.upload_rate;
    status->num_peers = native.num_peers;
    status->num_connections = native.num_connections;
    status->num_uploads = native.num_uploads;
    status->listen_port = session->session.listen_port();
    session->refresh_session_stats();
    status->dht_nodes = session->last_dht_nodes;
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
        char *path_copy = copy_c_string(path);
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

int32_t sgx_libtorrent_copy_trackers(SGXLibtorrentSession *session, int32_t handle_id, SGXTorrentTracker *trackers, int32_t max_trackers)
{
    auto *handle = session ? session->find(handle_id) : nullptr;
    if (handle == nullptr || trackers == nullptr || max_trackers <= 0) return 0;
    auto native = handle->trackers();
    int count = std::min(static_cast<int>(native.size()), max_trackers);
    for (int i = 0; i < count; ++i) {
        auto const &tracker = native[static_cast<std::size_t>(i)];
        std::string status = tracker_status(tracker);
        std::string last_announce;
        std::string next_announce;
        std::string error_message;
        int seed_count = -1;
        int leecher_count = -1;
        int downloaded_count = -1;
        if (!tracker.endpoints.empty()) {
            auto const &endpoint = tracker.endpoints.front();
            auto const &infohash = endpoint.info_hashes[lt::protocol_version::V1];
            last_announce = time_label(infohash.min_announce);
            next_announce = time_label(infohash.next_announce);
            error_message = infohash.last_error ? infohash.last_error.message() : infohash.message;
            seed_count = infohash.scrape_complete;
            leecher_count = infohash.scrape_incomplete;
            downloaded_count = infohash.scrape_downloaded;
        }
        trackers[i].url = copy_c_string(tracker.url);
        trackers[i].status = copy_c_string(status);
        trackers[i].last_announce = copy_c_string(last_announce);
        trackers[i].next_announce = copy_c_string(next_announce);
        trackers[i].error_message = copy_c_string(error_message);
        trackers[i].tier = tracker.tier;
        trackers[i].seed_count = seed_count;
        trackers[i].leecher_count = leecher_count;
        trackers[i].downloaded_count = downloaded_count;
    }
    return count;
}

void sgx_libtorrent_free_trackers(SGXTorrentTracker *trackers, int32_t tracker_count)
{
    if (trackers == nullptr) return;
    for (int32_t i = 0; i < tracker_count; ++i) {
        delete[] trackers[i].url;
        delete[] trackers[i].status;
        delete[] trackers[i].last_announce;
        delete[] trackers[i].next_announce;
        delete[] trackers[i].error_message;
        trackers[i].url = nullptr;
        trackers[i].status = nullptr;
        trackers[i].last_announce = nullptr;
        trackers[i].next_announce = nullptr;
        trackers[i].error_message = nullptr;
    }
}

int32_t sgx_libtorrent_copy_peers(SGXLibtorrentSession *session, int32_t handle_id, SGXTorrentPeer *peers, int32_t max_peers)
{
    auto *handle = session ? session->find(handle_id) : nullptr;
    if (handle == nullptr || peers == nullptr || max_peers <= 0) return 0;
    std::vector<lt::peer_info> native;
    handle->get_peer_info(native);
    int count = std::min(static_cast<int>(native.size()), max_peers);
    for (int i = 0; i < count; ++i) {
        auto const &peer = native[static_cast<std::size_t>(i)];
        std::string direction = (peer.flags & lt::peer_info::outgoing_connection) ? "out" : "in";
        peers[i].address = copy_c_string(peer.ip.address().to_string() + ":" + std::to_string(peer.ip.port()));
        peers[i].client = copy_c_string(peer.client);
        peers[i].direction = copy_c_string(direction);
        peers[i].flags = copy_c_string(peer_flags_label(peer));
        peers[i].progress = peer.progress;
        peers[i].download_rate = peer.down_speed;
        peers[i].upload_rate = peer.up_speed;
    }
    return count;
}

void sgx_libtorrent_free_peers(SGXTorrentPeer *peers, int32_t peer_count)
{
    if (peers == nullptr) return;
    for (int32_t i = 0; i < peer_count; ++i) {
        delete[] peers[i].address;
        delete[] peers[i].client;
        delete[] peers[i].direction;
        delete[] peers[i].flags;
        peers[i].address = nullptr;
        peers[i].client = nullptr;
        peers[i].direction = nullptr;
        peers[i].flags = nullptr;
    }
}

const char *sgx_libtorrent_last_error(SGXLibtorrentSession *session)
{
    if (session == nullptr) return "No libtorrent session";
    return session->last_error.c_str();
}
