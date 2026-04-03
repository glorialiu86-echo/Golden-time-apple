#!/usr/bin/env python3
"""
Golden-time 算法单元测试
不依赖模拟器，直接验证核心算法逻辑
"""

import math
from datetime import datetime, timezone, timedelta

def solve_altitude_crossing(day_start_ts, lat_deg, lon_deg, alt_deg, rising):
    """解析解：计算太阳穿越指定高度角的时间
    
    使用 NOAA 标准公式
    rising=True: 早晨太阳上升时穿越
    rising=False: 傍晚太阳下降时穿越
    """
    
    # 1. 计算儒略日和太阳赤纬
    jd = (day_start_ts / 86400.0) + 2440587.5
    jc = (jd - 2451545.0) / 36525.0
    
    # 太阳赤纬
    mean_long = (280.46646 + jc * (36000.76983 + jc * 0.0003032)) % 360
    mean_anom = (357.52911 + jc * (35999.05029 - 0.0001537 * jc)) % 360
    omega = 125.04 - 1934.136 * jc
    m_rad = math.radians(mean_anom)
    center = (math.sin(m_rad) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
              + math.sin(2.0 * m_rad) * (0.019993 - 0.000101 * jc)
              + math.sin(3.0 * m_rad) * 0.000289)
    true_long = mean_long + center
    eclip_long = true_long - 0.00569 - 0.00478 * math.sin(math.radians(omega))
    obliq_mean = 23.0 + (26.0 + ((21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60.0)) / 60.0
    obliq_corr = obliq_mean + 0.00256 * math.cos(math.radians(omega))
    eclip_rad = math.radians(eclip_long)
    obliq_rad = math.radians(obliq_corr)
    decl_rad = math.asin(math.sin(obliq_rad) * math.sin(eclip_rad))
    
    # 2. 计算时间方程（equation of time）
    var_y = math.tan(obliq_rad / 2.0) ** 2
    eq_of_time = 4.0 * math.degrees(
        var_y * math.sin(2.0 * math.radians(mean_long))
        - 2.0 * math.radians(mean_anom / 57.29578)
        + 4.0 * math.radians(mean_anom / 57.29578) * var_y * math.sin(2.0 * math.radians(mean_long))
        - 0.5 * var_y * var_y * math.sin(4.0 * math.radians(mean_long))
        - 1.25 * (math.radians(mean_anom / 57.29578)) ** 2 * math.sin(2.0 * math.radians(mean_anom))
    )
    
    # 3. 解时角方程
    lat_rad = math.radians(lat_deg)
    alt_rad = math.radians(alt_deg)
    
    sin_alt = math.sin(alt_rad)
    sin_lat = math.sin(lat_rad)
    cos_lat = math.cos(lat_rad)
    sin_decl = math.sin(decl_rad)
    cos_decl = math.cos(decl_rad)
    
    numerator = sin_alt - sin_lat * sin_decl
    denominator = cos_lat * cos_decl
    
    if abs(denominator) < 0.0001:
        return None, "denominator_too_small"
    
    cos_h = numerator / denominator
    
    if cos_h < -1.0 or cos_h > 1.0:
        return None, f"cosH_out_of_range_{cos_h:.4f}"
    
    hour_angle_deg = math.degrees(math.acos(cos_h))
    
    # 4. 计算太阳正午（NOAA 标准公式）
    # 注意：这里假设 day_start_ts 是 UTC 时间
    # 需要知道目标时区来计算本地太阳正午
    
    # 从经度推算时区（粗略估计）
    timezone_offset = round(lon_deg / 15.0)
    
    # solarNoon = 720 - 4*longitude - equationOfTime + timezone*60 (分钟)
    # 这个公式计算的是本地时间的太阳正午
    solar_noon_minutes = 720 - 4 * lon_deg - eq_of_time + timezone_offset * 60
    solar_noon_hour_local = solar_noon_minutes / 60.0
    
    # 5. 计算事件时间（本地时间）
    time_offset_hours = hour_angle_deg / 15.0
    
    if rising:
        event_hour_local = solar_noon_hour_local - time_offset_hours
    else:
        event_hour_local = solar_noon_hour_local + time_offset_hours
    
    # 确保在 [0, 24) 范围内
    if event_hour_local < 0:
        event_hour_local += 24
    elif event_hour_local >= 24:
        event_hour_local -= 24
    
    # 转换为 UTC 时间戳
    # event_hour_local 是本地时间，需要减去时区偏移得到 UTC 时间
    event_hour_utc = event_hour_local - timezone_offset
    
    # 转换为时间戳
    event_ts = day_start_ts + int(event_hour_utc * 3600)
    
    return event_ts, "success"

def test_shanghai_morning():
    """测试上海早晨的蓝调和金调"""
    print("=" * 60)
    print("测试：上海，2026-02-19 早晨")
    print("=" * 60)
    
    # 使用 UTC 时间作为 day_start
    day_start = datetime(2026, 2, 19, 0, 0, 0, tzinfo=timezone.utc)
    day_start_ts = int(day_start.timestamp())
    
    lat = 31.2304
    lon = 121.4737
    
    # 测试蓝调开始（-10°）
    blue_start_ts, blue_status = solve_altitude_crossing(day_start_ts, lat, lon, -10.0, True)
    
    # 测试金调开始（-4°）
    golden_start_ts, golden_status = solve_altitude_crossing(day_start_ts, lat, lon, -4.0, True)
    
    shanghai_tz = timezone(timedelta(hours=8))
    
    print(f"\n蓝调开始（-10°）：")
    if blue_start_ts:
        dt = datetime.fromtimestamp(blue_start_ts, tz=shanghai_tz)
        print(f"  ✅ 时间: {dt.strftime('%H:%M:%S')}")
        print(f"  时间戳: {blue_start_ts}")
    else:
        print(f"  ❌ 失败: {blue_status}")
    
    print(f"\n金调开始（-4°）：")
    if golden_start_ts:
        dt = datetime.fromtimestamp(golden_start_ts, tz=shanghai_tz)
        print(f"  ✅ 时间: {dt.strftime('%H:%M:%S')}")
        print(f"  时间戳: {golden_start_ts}")
    else:
        print(f"  ❌ 失败: {golden_status}")
    
    # 验证
    if blue_start_ts and golden_start_ts:
        diff_min = (golden_start_ts - blue_start_ts) // 60
        print(f"\n时间差: {diff_min} 分钟")
        
        # 检查是否是早晨时间（4:00-10:00）
        blue_dt = datetime.fromtimestamp(blue_start_ts, tz=shanghai_tz)
        golden_dt = datetime.fromtimestamp(golden_start_ts, tz=shanghai_tz)
        
        if 4 <= blue_dt.hour < 10 and 4 <= golden_dt.hour < 10:
            print(f"✅ 测试通过：时间在早晨范围内")
            return True
        else:
            print(f"❌ 测试失败：时间不在早晨范围（蓝调 {blue_dt.hour}:xx，金调 {golden_dt.hour}:xx）")
            return False
    else:
        print(f"❌ 测试失败：无法计算时间")
        return False

def test_current_time():
    """测试当前时间的倒计时"""
    print("\n" + "=" * 60)
    print("测试：当前时间倒计时")
    print("=" * 60)
    
    shanghai_tz = timezone(timedelta(hours=8))
    now = datetime.now(tz=shanghai_tz)
    now_ts = int(now.timestamp())
    
    # 今天和明天
    today_start = datetime(now.year, now.month, now.day, 0, 0, 0, tzinfo=shanghai_tz)
    today_start_ts = int(today_start.timestamp())
    tomorrow_start_ts = today_start_ts + 86400
    
    lat = 31.2304
    lon = 121.4737
    
    print(f"\n当前时间: {now.strftime('%Y-%m-%d %H:%M:%S')}")
    
    # 扫描今天和明天的早晨
    for day_name, day_ts in [("今天", today_start_ts), ("明天", tomorrow_start_ts)]:
        blue_ts, _ = solve_altitude_crossing(day_ts, lat, lon, -10.0, True)
        golden_ts, _ = solve_altitude_crossing(day_ts, lat, lon, -4.0, True)
        
        if blue_ts and blue_ts > now_ts:
            dt = datetime.fromtimestamp(blue_ts, tz=shanghai_tz)
            remaining = blue_ts - now_ts
            hours = remaining // 3600
            mins = (remaining % 3600) // 60
            print(f"\n{day_name}早晨蓝调: {dt.strftime('%H:%M')} (倒计时 {hours:02d}:{mins:02d})")
            
        if golden_ts and golden_ts > now_ts:
            dt = datetime.fromtimestamp(golden_ts, tz=shanghai_tz)
            remaining = golden_ts - now_ts
            hours = remaining // 3600
            mins = (remaining % 3600) // 60
            print(f"{day_name}早晨金调: {dt.strftime('%H:%M')} (倒计时 {hours:02d}:{mins:02d})")

if __name__ == '__main__':
    success = test_shanghai_morning()
    test_current_time()
    
    print("\n" + "=" * 60)
    if success:
        print("✅ 所有测试通过")
    else:
        print("❌ 测试失败")
    print("=" * 60)
