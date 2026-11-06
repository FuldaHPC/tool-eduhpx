// One HPX collective, flat or hierarchical, repeated: the examples of EduHPX.
//   COLL = bcast | reduce | allreduce | gather | allgather | scatter | alltoall | alltoall_large | alltoall_pairwise | scan_ex | scan_in | barrier
//   COLL_KIND = flat | hier   COLL_ARITY (hier, default 2)   COLL_ITER (default 10)   COLL_INTS (payload ints, default 1024)
#include <hpx/hpx_init.hpp>
#include <hpx/include/runtime.hpp>
#include <hpx/modules/collectives.hpp>
#include <hpx/thread.hpp>

#include <array>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <functional>
#include <iostream>
#include <string>
#include <type_traits>
#include <vector>

using namespace hpx::collectives;

static long env_long(char const* name, long def)
{
    char const* v = std::getenv(name);
    return (v != nullptr && *v != 0) ? std::atol(v) : def;
}
static std::string env_str(char const* name, char const* def)
{
    char const* v = std::getenv(name);
    return (v != nullptr && *v != 0) ? v : def;
}

template <typename Comm>
int run(Comm& comm, std::string const& coll, std::uint32_t here, std::uint32_t n, std::uint32_t root, int iterations,
    std::size_t ints)
{
    std::uint64_t checksum = 0;
    for (int i = 0; i != iterations; ++i)
    {
        std::uint32_t const gen = i + 1;
        if (coll == "bcast")
        {
            if (here == root)
            {
                std::vector<int> data(ints, i + 1);
                checksum += broadcast_to(comm, data).get().size();
            }
            else
                checksum += broadcast_from<std::vector<int>>(comm).get().size();
        }
        else if (coll == "reduce")
        {
            std::uint32_t v = here + i;
            if (here == root)
                checksum += reduce_here(comm, std::move(v), std::plus<std::uint32_t>{}).get();
            else
            {
                if constexpr (std::is_same_v<Comm, hpx::collectives::communicator>)
                    reduce_there(comm, std::move(v)).get();             // flat: the operator is given at the root only
                else
                    reduce_there(comm, std::move(v), std::plus<std::uint32_t>{}).get();
            }
        }
        else if (coll == "allreduce")
        {
            std::uint32_t v = here + i;
            checksum += all_reduce(comm, std::move(v), std::plus<std::uint32_t>{}, this_site_arg(here), generation_arg(gen)).get();
        }
        else if (coll == "gather")
        {
            std::vector<int> v(ints, here + i);
            if (here == root)
                checksum += gather_here(comm, std::move(v)).get().size();
            else
                gather_there(comm, std::move(v)).get();
        }
        else if (coll == "allgather")
        {
            std::vector<int> v(ints, here + i);
            checksum += all_gather(comm, std::move(v), this_site_arg(here), generation_arg(gen)).get().size();
        }
        else if (coll == "scatter")
        {
            if (here == root)
            {
                std::vector<std::vector<int>> data(n, std::vector<int>(ints, i + 1));
                checksum += scatter_to(comm, std::move(data)).get().size();
            }
            else
                checksum += scatter_from<std::vector<int>>(comm).get().size();
        }
        else if (coll == "alltoall")
        {
            std::vector<std::uint32_t> values(n, here + i);
            checksum += all_to_all(hpx::launch::sync, comm, std::move(values), this_site_arg(here), generation_arg(gen)).size();
        }
        else if (coll == "alltoall_large")
        {
            std::vector<std::vector<int>> values(n, std::vector<int>(ints, here + i));
            checksum += all_to_all(hpx::launch::sync, comm, std::move(values), this_site_arg(here), generation_arg(gen)).size();
        }
        else if (coll == "scan_ex")
        {
            checksum += exclusive_scan(comm, std::uint32_t(here + i), std::uint32_t(10 + i), std::plus<std::uint32_t>{},
                this_site_arg(here), generation_arg(gen)).get();
        }
        else if (coll == "scan_in")
        {
            checksum += inclusive_scan(comm, std::uint32_t(here + i), std::plus<std::uint32_t>{}, this_site_arg(here),
                generation_arg(gen)).get();
        }
        else if (coll == "barrier")
        {
            hpx::collectives::barrier(comm, this_site_arg(here), generation_arg(gen)).get();
        }
        else
        {
            std::cerr << "unknown COLL " << coll << std::endl;
            return 2;
        }
    }
    std::cerr << "locality " << here << "/" << n << " done: " << iterations << " x " << coll << ", checksum " << checksum << std::endl;
    return 0;
}

int hpx_main()
{
    std::uint32_t const here = hpx::get_locality_id();
    std::uint32_t const n = hpx::get_num_localities(hpx::launch::sync);
    std::uint32_t const root = 0;
    std::string const coll = env_str("COLL", "bcast");
    std::string const kind = env_str("COLL_KIND", "flat");
    int const iterations = static_cast<int>(env_long("COLL_ITER", 10));
    int const arity = static_cast<int>(env_long("COLL_ARITY", 2));
    std::size_t const ints = static_cast<std::size_t>(env_long("COLL_INTS", 1024));
    std::string const base = "/eduhpx/" + coll + "_" + kind + "/";
    int rc;
    if (coll == "alltoall_pairwise")
    {
        // all_to_all by name: from 4 KiB per destination on HPX leaves the central communicator and exchanges pairwise
        // (every locality sends to every other one) over channels
        std::uint64_t checksum = 0;
        for (int i = 0; i != iterations; ++i)
        {
            // a type of fixed size: HPX only decides for the pairwise exchange if it knows the bytes per destination
            std::vector<std::array<int, 2048>> values(n);
            for (auto& block : values)
                block.fill(static_cast<int>(here) + i);
            checksum += all_to_all(base.c_str(), std::move(values), num_sites_arg(n), this_site_arg(here),
                generation_arg(i + 1)).get().size();
        }
        std::cerr << "locality " << here << "/" << n << " done: " << iterations << " x " << coll << ", checksum " << checksum << std::endl;
        hpx::finalize();
        (void) ints;
        return 0;
    }
    if (kind == "hier")
    {
        auto comm = create_hierarchical_communicator(base.c_str(), num_sites_arg(n), this_site_arg(here), arity_arg(arity),
            generation_arg(), root_site_arg(root), flat_fallback_threshold_arg(0));
        hpx::this_thread::sleep_for(std::chrono::milliseconds(500));    // all communicators exist: a pause between set-up and work
        rc = run(comm, coll, here, n, root, iterations, ints);
    }
    else
    {
        auto comm = create_communicator(base.c_str(), num_sites_arg(n), this_site_arg(here), generation_arg(), root_site_arg(root));
        hpx::this_thread::sleep_for(std::chrono::milliseconds(500));
        rc = run(comm, coll, here, n, root, iterations, ints);
    }
    hpx::finalize();
    return rc;
}

int main(int argc, char* argv[])
{
    return hpx::init(argc, argv);
}
