// The texture C ABI's behaviour (OxidANT abi/texture.json) as both desktop gtests run it; each defines AbiTexture.

TEST(TextureAbi, ANewTextureShowsItsColourOpaqueUntilAFrameArrives)
{
    AbiTexture texture(2, 1, 10, 20, 30);
    const AbiFrame frame = texture.frame();
    EXPECT_EQ(frame.width, 2U);
    EXPECT_EQ(frame.height, 1U);
    EXPECT_EQ(frame.bytes, (std::vector<uint8_t>{ 10, 20, 30, 255, 10, 20, 30, 255 }));
}

TEST(TextureAbi, OnlyARegisteredIdTakesAFrame)
{
    const std::vector<uint8_t> pixel{ 1, 2, 3, 4 };
    EXPECT_EQ(knt_push_frame(7101, pixel.data(), 1, 1), KNT_UNKNOWN_TEXTURE);
    AbiTexture texture(1, 1, 0, 0, 0);
    texture.register_as(7101);
    EXPECT_EQ(knt_push_frame(7101, pixel.data(), 1, 1), KNT_OK);
    AbiTexture::unregister(7101);
    EXPECT_EQ(knt_push_frame(7101, pixel.data(), 1, 1), KNT_UNKNOWN_TEXTURE);
}

TEST(TextureAbi, BadArgumentsAreRefusedAndChangeNothing)
{
    AbiTexture texture(1, 1, 9, 9, 9);
    texture.register_as(7102);
    const std::vector<uint8_t> pixel{ 1, 2, 3, 4 };
    EXPECT_EQ(knt_push_frame(7102, nullptr, 1, 1), KNT_BAD_ARGUMENTS);
    EXPECT_EQ(knt_push_frame(7102, pixel.data(), 0, 1), KNT_BAD_ARGUMENTS);
    EXPECT_EQ(knt_push_frame(7102, pixel.data(), 1, 0), KNT_BAD_ARGUMENTS);
    EXPECT_EQ(texture.frame().bytes, (std::vector<uint8_t>{ 9, 9, 9, 255 }));
    AbiTexture::unregister(7102);
}

// Owner decision 2026-11-13: Windows is the rule, so the texture takes the pushed frame's size and its alpha as sent.
TEST(TextureAbi, APushedFrameWinsAtItsOwnSizeWithItsAlphaAsSent)
{
    AbiTexture texture(4, 4, 0, 0, 255);
    texture.register_as(7103);
    const std::vector<uint8_t> wide{ 10, 20, 30, 0, 40, 50, 60, 128, 70, 80, 90, 255 };
    ASSERT_EQ(knt_push_frame(7103, wide.data(), 3, 1), KNT_OK);
    AbiFrame frame = texture.frame();
    EXPECT_EQ(frame.width, 3U);
    EXPECT_EQ(frame.height, 1U);
    EXPECT_EQ(frame.bytes, wide);
    const std::vector<uint8_t> tall{ 1, 2, 3, 4, 5, 6, 7, 8 };
    ASSERT_EQ(knt_push_frame(7103, tall.data(), 1, 2), KNT_OK);
    frame = texture.frame();
    EXPECT_EQ(frame.width, 1U);
    EXPECT_EQ(frame.height, 2U);
    EXPECT_EQ(frame.bytes, tall);
    AbiTexture::unregister(7103);
}

// Raw mt19937 output, not a distribution, so both standard libraries replay the same 300 steps.
TEST(TextureAbi, SeededPushesOfRandomSizesNullBuffersAndUnknownIdsKeepTheLastGoodFrame)
{
    AbiTexture texture(1, 1, 0, 0, 0);
    texture.register_as(7104);
    std::mt19937 random(20261128U);
    AbiFrame last{ 1, 1, { 0, 0, 0, 255 } };
    for (int step = 0; step < 300; ++step) {
        const auto kind = static_cast<uint32_t>(random() % 4U);
        auto width = static_cast<uint32_t>(random() % 48U + 1U);
        auto height = static_cast<uint32_t>(random() % 48U + 1U);
        std::vector<uint8_t> rgba(static_cast<size_t>(width) * height * 4U);
        for (uint8_t &value : rgba) { value = static_cast<uint8_t>(random()); }
        // After the fill, so a zero side still comes with a real buffer and only the size check can refuse it.
        if (kind == 3U) { (random() % 2U == 0U ? width : height) = 0U; }
        // 7105 is never registered; a zero side and a null buffer go to the registered id.
        const int64_t id = kind == 1U ? 7105 : 7104;
        const uint8_t *data = kind == 2U ? nullptr : rgba.data();
        const int32_t expected = kind == 0U ? KNT_OK : (kind == 1U ? KNT_UNKNOWN_TEXTURE : KNT_BAD_ARGUMENTS);
        ASSERT_EQ(knt_push_frame(id, data, width, height), expected) << "step " << step << ", kind " << kind;
        if (kind == 0U) { last = AbiFrame{ width, height, rgba }; }
        const AbiFrame frame = texture.frame();
        ASSERT_EQ(frame.width, last.width) << "step " << step;
        ASSERT_EQ(frame.height, last.height) << "step " << step;
        ASSERT_EQ(frame.bytes, last.bytes) << "step " << step;
    }
    AbiTexture::unregister(7104);
}
