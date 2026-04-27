use xiangmu;

-- =============================================
-- 项目：olist 电商经营分析项目
-- 文件：01_03_main_analysis.sql
-- 作用：构建经营主线分析框架，覆盖数据摸底、经营表现、区域差异、履约效率与支付结构
-- =============================================

/*

一、分析目标
本脚本用于构建 Olist 平台的大盘经营分析主线，重点回答：

1. 平台整体交易规模如何
2. 平台是否处于增长阶段
3. 交易、履约与区域表现是否存在明显差异
4. 平台支付结构与分期结构呈现什么特征

二、数据范围
本脚本使用：
- olist_orders_dataset
- olist_customers_dataset
- olist_order_payments_dataset

暂未引入：
- olist_order_items_dataset
- 运费拆解相关分析

三、口径说明
1. 金额口径：
   所有金额指标（gmv、aov、各维度支付金额）统一基于支付表汇总后得到。
   为避免同一订单存在多条支付记录导致重复统计，统一先按订单粒度汇总 payment_value。

2. 订单口径：
   除特别说明外，经营类指标默认只统计已完成订单（order_status = 'delivered'）。

3. 失败口径：
   终态失败率默认基于终态订单（delivered / canceled / unavailable）计算，
   仅用于衡量平台整体终态质量，不展开取消风险专题分析。

*/

-- =============================================
-- 0. 数据预览
-- =============================================

select * from olist_orders_dataset limit 5;
select * from olist_customers_dataset limit 5;
select * from olist_order_payments_dataset limit 5;

-- =============================================
-- 1. 数据摸底（data check）
-- 先确认数据时间范围、订单状态和整体规模
-- =============================================

-- 1.1 时间窗口界定
select
    min(order_purchase_timestamp) as start_date,
    max(order_purchase_timestamp) as end_date
from olist_orders_dataset;
-- 时间段：2016-09-14 ~ 2018-10-17

-- 1.2 订单状态分布
select
    order_status,
    count(*) as cnt
from olist_orders_dataset
group by order_status
order by cnt desc;

-- 1.3 各州订单量
select
    c.customer_state,
    count(distinct o.order_id) as order_cnt
from olist_orders_dataset o
         join olist_customers_dataset c
              on o.customer_id = c.customer_id
group by c.customer_state
order by order_cnt desc;

-- 1.4 终态失败率（只看 delivered / canceled / unavailable）
select
    round(
            sum(order_status in ('canceled', 'unavailable')) / count(*) * 100,
            2
    ) as fail_rate_pct
from olist_orders_dataset
where order_status in ('delivered', 'canceled', 'unavailable');
-- 终态失败率约 1.26%
