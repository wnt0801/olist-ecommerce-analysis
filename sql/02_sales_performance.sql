use xiangmu;

-- =============================================
-- 2. 核心经营指标
-- 只看 delivered，保证口径统一
-- =============================================

with payment_agg as (
    select
        order_id,
        sum(payment_value) as payment_value
    from olist_order_payments_dataset
    group by order_id
)
select
    round(sum(p.payment_value), 2) as '成交总额',
    count(distinct o.order_id) as '有效订单量',
    round(sum(p.payment_value) / count(distinct o.order_id), 2) as '客单价'
from olist_orders_dataset o
         join payment_agg p
              on o.order_id = p.order_id
where o.order_status = 'delivered';
-- 成交总额: 15422462
-- 有效订单量: 96477
-- 客单价: 159.86

-- =============================================
-- 3. 月度经营趋势
-- 看平台增长情况
-- =============================================

with payment_agg as (
    select
        order_id,
        sum(payment_value) as payment_value
    from olist_order_payments_dataset
    group by order_id
)
select
    date_format(o.order_purchase_timestamp, '%Y-%m-01') as '月份',
    round(sum(p.payment_value), 2) as '月度成交总额',
    count(distinct o.order_id) as '月度有效订单数',
    round(sum(p.payment_value) / count(distinct o.order_id), 2) as '月度客单价'
from olist_orders_dataset o
         join payment_agg p
              on o.order_id = p.order_id
where o.order_status = 'delivered'
group by date_format(o.order_purchase_timestamp, '%Y-%m-01')
order by date_format(o.order_purchase_timestamp, '%Y-%m-01');
-- 一年多时间里平台实现近 10 倍增长
-- 2016-10、2016-12订单极少，做图时建议剔除；且缺少2016-11

-- =============================================
-- 4. 区域分析
-- 看不同州的经营规模、质量和效率差异
-- =============================================

-- 4.1 各州 gmv / 订单量 / aov
with payment_agg as (
    select
        order_id,
        sum(payment_value) as payment_value
    from olist_order_payments_dataset
    group by order_id
)
select
    c.customer_state as '地区',
    round(sum(p.payment_value), 2) as '成交总额',
    count(distinct o.order_id) as '有效订单量',
    round(sum(p.payment_value) / count(distinct o.order_id), 2) as '客单价'
from olist_orders_dataset o
         join olist_customers_dataset c
              on o.customer_id = c.customer_id
         join payment_agg p
              on o.order_id = p.order_id
where o.order_status = 'delivered'
group by c.customer_state
order by round(sum(p.payment_value), 2) desc;

-- 4.2 各州终态失败率（只看 delivered / canceled / unavailable）
select
    c.customer_state as '地区',
    count(distinct o.order_id) as '终态订单数',
    count(distinct case when o.order_status in ('canceled', 'unavailable') then o.order_id end) as '失败订单数',
    round(
            count(distinct case when o.order_status in ('canceled', 'unavailable') then o.order_id end)
                / count(distinct o.order_id) * 100,
            2
    ) as '终态失败率'
from olist_orders_dataset o
         left join olist_customers_dataset c
                   on o.customer_id = c.customer_id
where o.order_status in ('delivered', 'canceled', 'unavailable')
group by c.customer_state
order by 4 desc;
-- 小样本州波动大，分析时需谨慎

/*
区域分析结论：
平台订单与收入高度集中于少数核心州，其中 sp 州在订单量和 gmv 上显著领先，且失败率相对较低，
体现出较强的经营稳定性。相比之下，部分尾部州虽然订单规模较小，但失败率明显偏高，
说明区域经营质量存在显著差异，不能仅以订单规模判断区域表现。
*/

-- =============================================
-- 5. 履约分析
-- 看配送效率和异常值影响
-- =============================================

-- 5.1 配送时长极值和均值（先看全量，再看剔除 >90 天长尾后的结果）

-- 全量 delivered 订单
select
    min(datediff(order_delivered_customer_date, order_purchase_timestamp)) as min_days,
    max(datediff(order_delivered_customer_date, order_purchase_timestamp)) as max_days,
    round(avg(datediff(order_delivered_customer_date, order_purchase_timestamp)), 2) as avg_days
from olist_orders_dataset
where order_status = 'delivered'
  and order_delivered_customer_date is not null
  and order_purchase_timestamp is not null;
-- 全量订单：最小 0 天，最大 210 天，平均配送时长约 12.5 天

-- 剔除 > 90 天长尾订单后
select
    min(datediff(order_delivered_customer_date, order_purchase_timestamp)) as min_days,
    max(datediff(order_delivered_customer_date, order_purchase_timestamp)) as max_days,
    round(avg(datediff(order_delivered_customer_date, order_purchase_timestamp)), 2) as avg_days
from olist_orders_dataset
where order_status = 'delivered'
  and order_delivered_customer_date is not null
  and order_purchase_timestamp is not null
  and datediff(order_delivered_customer_date, order_purchase_timestamp) < 90;
-- 剔除极端长尾订单后，平均配送时长约 12.4 天

-- 5.2 各州平均配送时长
-- 为避免小样本州波动过大，仅保留订单量不少于 100 的州
select
    c.customer_state as '地区',
    count(distinct o.order_id) as '订单量',
    round(avg(datediff(o.order_delivered_customer_date, o.order_purchase_timestamp)), 2) as '平均配送天数'
from olist_orders_dataset o
         join olist_customers_dataset c
              on o.customer_id = c.customer_id
where o.order_status = 'delivered'
  and o.order_delivered_customer_date is not null
  and datediff(o.order_delivered_customer_date, o.order_purchase_timestamp) < 90
group by c.customer_state
having count(distinct o.order_id) >= 100
order by round(avg(datediff(o.order_delivered_customer_date, o.order_purchase_timestamp)), 2) desc;

-- =============================================
-- 6. 三表合一：区域经营 + 质量 + 履约
-- 输出州维度经营总表
-- =============================================

with payment_agg as (
    select
        order_id,
        sum(payment_value) as payment_value
    from olist_order_payments_dataset
    group by order_id
),
     region_base as (
         select
             c.customer_state,
             round(sum(case when o.order_status = 'delivered' then p.payment_value else 0 end), 2) as gmv,
             count(distinct case when o.order_status = 'delivered' then o.order_id end) as order_cnt,
             round(
                     sum(case when o.order_status = 'delivered' then p.payment_value else 0 end)
                         / nullif(count(distinct case when o.order_status = 'delivered' then o.order_id end), 0),
                     2
             ) as aov,
             round(
                     count(distinct case when o.order_status in ('canceled', 'unavailable') then o.order_id end) * 100.0
                         / nullif(count(distinct case when o.order_status in ('delivered', 'canceled', 'unavailable') then o.order_id end), 0),
                     2
             ) as fail_rate_pct,
             round(
                     avg(
                             case
                                 when o.order_status = 'delivered'
                                     and o.order_delivered_customer_date is not null
                                     and datediff(o.order_delivered_customer_date, o.order_purchase_timestamp) < 90
                                     then datediff(o.order_delivered_customer_date, o.order_purchase_timestamp)
                                 end
                     ),
                     2
             ) as avg_delivery_days
         from olist_orders_dataset o
                  join olist_customers_dataset c
                       on o.customer_id = c.customer_id
                  left join payment_agg p
                            on o.order_id = p.order_id
         group by c.customer_state
     )
select
    customer_state,
    gmv,
    order_cnt,
    aov,
    fail_rate_pct,
    avg_delivery_days
from region_base
order by gmv desc;
