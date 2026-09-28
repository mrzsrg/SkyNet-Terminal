using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

// SkyImagePrep — утолщение тонких контурных линий перед подачей в chafa.
// Используется модулем SkyNet.T800.psm1 для кадров вращения: если исходный PNG —
// прозрачный контурный арт (тонкие непрозрачные штрихи на прозрачном фоне), при
// сильном уменьшении для терминала (в ~15-25 раз по каждой оси) большинство штрихов
// проваливается между отсчётами chafa, и голова рендерится почти пустой. Дилатация
// альфа-канала на 2-3px решает это: заполнение "видимых" субпикселей вырастает
// с ~28% до ~99% при сохранении узнаваемости рисунка.
public static class SkyImagePrep
{
    // Возвращает долю пикселей с alpha > threshold (0..1). Для картинок без
    // альфа-канала (Format без Alpha) возвращает -1 — значит дилатация не нужна/невозможна.
    public static double MeasureInkCoverage(string path, byte alphaThreshold)
    {
        using (var src = new Bitmap(path))
        {
            if (!Image.IsAlphaPixelFormat(src.PixelFormat)) { return -1.0; }
            int w = src.Width, h = src.Height;
            var rect = new Rectangle(0, 0, w, h);
            var data = src.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                byte[] bytes = new byte[data.Stride * h];
                Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
                long ink = 0;
                for (int y = 0; y < h; y++)
                {
                    int row = y * data.Stride;
                    for (int x = 0; x < w; x++)
                    {
                        if (bytes[row + x * 4 + 3] > alphaThreshold) { ink++; }
                    }
                }
                return (double)ink / (w * (long)h);
            }
            finally { src.UnlockBits(data); }
        }
    }

    // Дилатация альфа-маски (сепарабельный проход X, затем Y — быстрее полного NxN)
    // с заливкой результата одним сплошным цветом инк-а (картинка предполагается
    // монохромной штриховкой; для многоцветного арта используйте другой инструмент).
    public static bool DilateAlpha(string srcPath, string dstPath, int radius, byte alphaThreshold,
        byte inkR, byte inkG, byte inkB)
    {
        try
        {
            using (var src = new Bitmap(srcPath))
            {
                int w = src.Width, h = src.Height;
                var rect = new Rectangle(0, 0, w, h);
                var srcData = src.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                byte[] srcBytes = new byte[srcData.Stride * h];
                Marshal.Copy(srcData.Scan0, srcBytes, 0, srcBytes.Length);
                int stride = srcData.Stride;
                src.UnlockBits(srcData);

                byte[] mask = new byte[w * h];
                for (int y = 0; y < h; y++)
                {
                    int row = y * stride;
                    int mrow = y * w;
                    for (int x = 0; x < w; x++)
                    {
                        mask[mrow + x] = srcBytes[row + x * 4 + 3] > alphaThreshold ? (byte)1 : (byte)0;
                    }
                }

                byte[] tmp = new byte[w * h];
                for (int y = 0; y < h; y++)
                {
                    int mrow = y * w;
                    for (int x = 0; x < w; x++)
                    {
                        byte v = 0;
                        int xs = x - radius; if (xs < 0) { xs = 0; }
                        int xe = x + radius; if (xe > w - 1) { xe = w - 1; }
                        for (int xx = xs; xx <= xe; xx++) { if (mask[mrow + xx] != 0) { v = 1; break; } }
                        tmp[mrow + x] = v;
                    }
                }
                byte[] outMask = new byte[w * h];
                for (int x = 0; x < w; x++)
                {
                    for (int y = 0; y < h; y++)
                    {
                        byte v = 0;
                        int ys = y - radius; if (ys < 0) { ys = 0; }
                        int ye = y + radius; if (ye > h - 1) { ye = h - 1; }
                        for (int yy = ys; yy <= ye; yy++) { if (tmp[yy * w + x] != 0) { v = 1; break; } }
                        outMask[y * w + x] = v;
                    }
                }

                using (var dst = new Bitmap(w, h, PixelFormat.Format32bppArgb))
                {
                    var dstData = dst.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                    byte[] dstBytes = new byte[dstData.Stride * h];
                    int dstStride = dstData.Stride;
                    for (int y = 0; y < h; y++)
                    {
                        int row = y * dstStride;
                        int mrow = y * w;
                        for (int x = 0; x < w; x++)
                        {
                            int i = row + x * 4;
                            if (outMask[mrow + x] != 0)
                            {
                                dstBytes[i + 0] = inkB;
                                dstBytes[i + 1] = inkG;
                                dstBytes[i + 2] = inkR;
                                dstBytes[i + 3] = 255;
                            }
                            else
                            {
                                dstBytes[i + 0] = 0; dstBytes[i + 1] = 0; dstBytes[i + 2] = 0; dstBytes[i + 3] = 255;
                            }
                        }
                    }
                    Marshal.Copy(dstBytes, 0, dstData.Scan0, dstBytes.Length);
                    dst.UnlockBits(dstData);
                    dst.Save(dstPath, ImageFormat.Png);
                }
            }
            return true;
        }
        catch { return false; }
    }
}
