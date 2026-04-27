-- 项目：olist 电商经营分析项目
-- 文件：11_summary_kpi.sql
-- 作用：提取总览页核心 kpi 指标


with payment_agg as (
    select
        order_id,
        sum(payment_value) as payment_value
    from olist_order_payments_dataset
    group by order_id
),

trade_kpi as (
    select
        round(sum(p.payment_value), 2) as gmv,
        count(distinct o.order_id) as valid_order_cnt,
        round(sum(p.payment_value) / count(distinct o.order_id), 2) as aov
    from olist_orders_dataset o
    join payment_agg p
        on o.order_id = p.order_id
    where o.order_status = 'delivered'
),

customer_kpi as (
    select
        count(distinct c.customer_unique_id) as unique_customer_cnt
    from olist_orders_dataset o
    join olist_customers_dataset c
        on o.customer_id = c.customer_id
    where o.order_status = 'delivered'
),

fail_kpi as (
    select
        round(
            sum(order_status in ('canceled', 'unavailable')) / count(*) * 100,
            2
        ) as fail_rate_pct
    from olist_orders_dataset
    where order_status in ('delivered', 'canceled', 'unavailable')
),

delivery_kpi as (
    select
        round(avg(datediff(order_delivered_customer_date, order_purchase_timestamp)), 2) as avg_delivery_days
    from olist_orders_dataset
    where order_status = 'delivered'
      and order_delivered_customer_date is not null
      and order_purchase_timestamp is not null
)

select
    t.gmv as '成交总额',
    t.valid_order_cnt as '有效订单量',
    t.aov as '客单价',
    c.unique_customer_cnt as '去重买家数',
    f.fail_rate_pct as '终态失败率(%)',
    d.avg_delivery_days as '平均配送天数(天)'
from trade_kpi t
cross join customer_kpi c
cross join fail_kpi f
cross join delivery_kpi d;
