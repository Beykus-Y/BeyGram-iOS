#include "BGMediaMixPreparation.hpp"

#include "bgmedia/analysis/Analyzer.hpp"
#include "bgmedia/analysis/AnalysisResult.hpp"
#include "bgmedia/cache/AnalysisCache.hpp"
#include "bgmedia/mix/MixFeatureCache.hpp"
#include "bgmedia/mix/PcmTrack.hpp"

#include <algorithm>
#include <memory>
#include <optional>

namespace beygram::media {
namespace {

void report(const MixPreparationProgress& progress, float fraction,
            std::string_view stage) {
    if (progress) {
        progress(std::clamp(fraction, 0.0f, 1.0f), stage);
    }
}

} // namespace

bool prepareMixTrack(const std::filesystem::path& path,
                     const MixDecodeFunction& decode,
                     const MixPreparationOptions& options,
                     bgmedia::mix::PreparedMixTrack& out, std::string& error,
                     const MixPreparationProgress& progress) {
    out = {};
    if (!decode) {
        error = "No decoder configured.";
        return false;
    }

    report(progress, 0.02f, "decoding audio");
    bgmedia::AudioData decoded;
    if (!decode(path, decoded, error)) {
        return false;
    }
    if (!decoded.valid()) {
        error = "Decoded audio is empty or has an unsupported layout.";
        return false;
    }

    std::string pcmError;
    const bgmedia::PcmBuffer pcm =
        bgmedia::PcmBuffer::fromAudio(decoded, &pcmError);
    if (!pcm.valid()) {
        error = "Could not prepare PCM: " + pcmError;
        return false;
    }

    const bool useCache = options.useCache && !options.cacheDirectory.empty();

    report(progress, 0.22f, "checking cache");
    std::optional<bgmedia::AnalysisResult> cached;
    if (useCache) {
        bgmedia::AnalysisCache cache(options.cacheDirectory);
        bgmedia::CacheLoadResult loaded = cache.load(pcm, options.analysis);
        if (loaded.hit()) {
            cached = std::move(loaded.result);
        }
    }

    auto analysis = std::make_shared<bgmedia::AnalysisResult>();
    if (cached) {
        *analysis = std::move(*cached);
        report(progress, 0.78f, "loaded analysis from cache");
    } else {
        bgmedia::Analyzer analyzer(options.analysis);
        report(progress, 0.25f, "analysing");
        bgmedia::AnalysisReport analysisReport = analyzer.analyze(
            pcm, [&](float fraction, const std::string& stage) {
                report(progress, 0.25f + 0.52f * fraction, stage);
            });
        if (!analysisReport.ok()) {
            error = analysisReport.status == bgmedia::AnalysisStatus::Cancelled
                        ? "analysis cancelled"
                        : analysisReport.message;
            return false;
        }
        *analysis = std::move(analysisReport.result);
        if (useCache) {
            report(progress, 0.79f, "saving analysis cache");
            bgmedia::AnalysisCache cache(options.cacheDirectory);
            std::string cacheError;
            (void)cache.store(*analysis, pcm, options.analysis, &cacheError);
        }
    }

    report(progress, 0.82f, "building feature map");
    std::optional<bgmedia::mix::MixFeatureMap> cachedFeatures;
    if (useCache) {
        bgmedia::mix::MixFeatureCache featureCache(options.cacheDirectory);
        bgmedia::mix::FeatureCacheLoadResult loadedFeatures =
            featureCache.load(decoded, pcm, *analysis, options.features);
        if (loadedFeatures.hit()) {
            cachedFeatures = std::move(loadedFeatures.features);
        }
    }
    auto features = std::make_shared<bgmedia::mix::MixFeatureMap>();
    if (cachedFeatures) {
        *features = std::move(*cachedFeatures);
    } else {
        bgmedia::mix::MixFeatureExtractor extractor(options.features);
        *features = extractor.extract(decoded, pcm, *analysis);
        if (useCache && features->valid()) {
            bgmedia::mix::MixFeatureCache featureCache(options.cacheDirectory);
            std::string featureCacheError;
            (void)featureCache.store(*features, options.features,
                                     &featureCacheError);
        }
    }

    report(progress, 0.90f, "preparing mixer audio");
    std::string trackError;
    auto track = std::make_shared<bgmedia::mix::PcmTrack>(
        bgmedia::mix::PcmTrack::fromAudio(decoded, options.targetSampleRate,
                                          &trackError));
    if (!track->valid()) {
        error = "Could not prepare mixer audio: " + trackError;
        return false;
    }

    out.audio = std::move(track);
    out.analysis = std::move(analysis);
    out.features = std::move(features);
    report(progress, 1.0f, "ready");
    return true;
}

} // namespace beygram::media
