-- 项目：olist 电商经营分析项目
-- 文件：12_monthly_business_trend.sql
-- 作用：提取月度经营趋势分析数据

with payment_agg as (
    select
        order_id,
        sum(payment_value) as payment_value
    from olist_order_payments_dataset
    group by order_id
)

select
    date_format(o.order_purchase_timestamp, '%y-%m-01') as '月份',
    round(sum(p.payment_value), 2) as '成交总额',
    count(distinct o.order_id) as '有效订单量',
    round(sum(p.payment_value) / count(distinct o.order_id), 2) as '客单价'
from olist_orders_dataset o
         join payment_agg p
              on o.order_id = p.order_id
where o.order_status = 'delivered'
group by date_format(o.order_purchase_timestamp, '%y-%m-01')
order by date_format(o.order_purchase_timestamp, '%y-%m-01');
