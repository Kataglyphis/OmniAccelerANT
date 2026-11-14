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
