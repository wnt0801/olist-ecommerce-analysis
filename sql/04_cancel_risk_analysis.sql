use xiangmu;

-- =============================================
-- 项目：olist 电商经营分析项目
-- 文件：04_cancel_risk_analysis.sql
-- 作用：识别取消风险订单特征，定位取消发生阶段与干预窗口
-- =============================================

/*

一、分析目标
本脚本用于回答三个问题：

1. 哪类订单更容易被取消
2. 取消主要发生在订单流程的哪个阶段
3. 取消问题是否来自物流履约，而非支付决策

二、数据范围
使用：
- olist_orders_dataset
- olist_order_payments_dataset
- olist_customers_dataset

暂未引入商品明细表，因此无法进一步验证品类影响。

三、口径说明
1. 取消口径：order_status = 'canceled'
   不含 unavailable，后者属于平台侧库存问题，性质不同

2. 金额口径：
   所有订单金额统一基于支付表 payment_value 汇总到订单粒度后分析

3. 目的：
   本文件聚焦“取消风险识别”，不重复展开经营大盘分析

*/

-- =============================================
-- 0. 州维度排查：确认取消问题是否具有明显区域集中性
-- =============================================

select c.customer_state,
       count(*)                                                     as total_orders,
       sum(case when o.order_status = 'canceled' then 1 else 0 end) as cancel_orders,
       round(
               100.0 * sum(case when o.order_status = 'canceled' then 1 else 0 end) / count(*),
               2
       )                                                            as cancel_rate_pct
from olist_orders_dataset o
         join olist_customers_dataset c
              on o.customer_id = c.customer_id
group by c.customer_state
having count(*) > 100
order by cancel_rate_pct desc;

/*
结论：
1. sp 州取消率 0.78%，在大州中相对偏高
2. ro、pi 等州取消率更高，但订单量较小，样本稳定性不足
3. 州维度可以提示风险，但不能解释取消本质
4. 因此后续分析转向订单结构本身
*/

-- =============================================
-- 1. 风险订单特征：取消订单 vs 完成订单均价
-- =============================================

select o.order_status,
       round(avg(cast(p.payment_value as float)), 2) as avg_value
from olist_orders_dataset o
         join olist_order_payments_dataset p
              on o.order_id = p.order_id
where o.order_status in ('delivered', 'canceled')
group by o.order_status;

/*
结论：
1. 取消订单均价 157.71，完成订单均价 136.39
2. 取消订单客单价高出 16%
3. 取消并不主要来自低价冲动购买，高客单价订单反而更容易被取消
*/

-- =============================================
-- 2. 取消订单价格分段：确认高价区间风险暴露
-- =============================================

select case
           when cast(p.payment_value as float) < 50 then '1_0-50'
           when cast(p.payment_value as float) < 150 then '2_50-150'
           when cast(p.payment_value as float) < 300 then '3_150-300'
           else '4_300+'
           end  as price_range,
       count(*) as cancel_count
from olist_orders_dataset o
         join olist_order_payments_dataset p
              on o.order_id = p.order_id
where o.order_status = 'canceled'
group by price_range
order by price_range;

/*
结论：
1. 50-150 区间取消绝对量最高
2. 300+ 高价区间仍有明显取消量
3. 结合均价结论，高价订单虽然不是数量最多，但单笔损失更大
*/

-- =============================================
-- 3. 高风险支付方式：voucher 完成 vs 取消
-- =============================================

-- 3.1 各支付方式取消单数
select p.payment_type,
       count(*) as cancel_count
from olist_orders_dataset o
         join olist_order_payments_dataset p
              on o.order_id = p.order_id
where o.order_status = 'canceled'
group by p.payment_type
order by cancel_count desc;

-- 3.2 voucher 完成 vs 取消对比
select o.order_status,
       count(*)                                      as order_count,
       round(avg(cast(p.payment_value as float)), 2) as avg_value
from olist_orders_dataset o
         join olist_order_payments_dataset p
              on o.order_id = p.order_id
where p.payment_type = 'voucher'
group by o.order_status
order by order_count desc;

/*
结论：
1. voucher 取消单数高于 boleto，风险水平异常
2. voucher 取消均价 223.17，是 voucher 完成订单均价 62.45 的 3.6 倍
3. voucher 降低了下单门槛，但没有降低商品本身价格压力
4. 高客单价 + voucher 是平台最危险的取消组合
*/

-- =============================================
-- 4. 高风险组合验证：支付方式 × 客单价区间
-- =============================================

with order_payment as (select o.order_id,
                              o.order_status,
                              p.payment_type,
                              sum(p.payment_value) as order_payment_value
                       from olist_orders_dataset o
                                join olist_order_payments_dataset p
                                     on o.order_id = p.order_id
                       group by o.order_id,
                                o.order_status,
                                p.payment_type),
     tagged as (select order_id,
                       order_status,
                       payment_type,
                       order_payment_value,
                       case
                           when order_payment_value < 50 then '1_0-50'
                           when order_payment_value < 150 then '2_50-150'
                           when order_payment_value < 300 then '3_150-300'
                           else '4_300+'
                           end as price_range
                from order_payment)
select payment_type,
       price_range,
       count(*)                                                   as total_orders,
       sum(case when order_status = 'canceled' then 1 else 0 end) as canceled_orders,
       round(
               100.0 * sum(case when order_status = 'canceled' then 1 else 0 end) / count(*),
               2
       )                                                          as cancel_rate_pct
from tagged
group by payment_type, price_range
having count(*) >= 30
order by payment_type, price_range;

/*
结论：
1. voucher 在各价格段取消率均高于主流支付方式
2. voucher 在 300+ 区间取消率高达 11.76%
3. 同价位 credit_card 仅 0.79%，说明高价本身不是核心风险源
4. voucher 在 300+ 区间取消率 11.76%，而 credit_card 同价位只有 0.79%，差距 15 倍
*/

-- =============================================
-- 5. 取消发生阶段：订单流程漏斗拆解
-- =============================================

select case
           when o.order_status = 'canceled' and o.order_approved_at is null
               then '1_未审核即取消'
           when o.order_status = 'canceled'
               and o.order_approved_at is not null
               and o.order_delivered_carrier_date is null
               then '2_审核后发货前取消'
           when o.order_status = 'canceled'
               and o.order_delivered_carrier_date is not null
               then '3_发货后取消'
           else '4_非取消订单'
           end  as stage_tag,
       count(*) as order_cnt
from olist_orders_dataset o
group by stage_tag
order by stage_tag;

-- 只看取消订单内部结构
select case
           when o.order_approved_at is null
               then '1_未审核即取消'
           when o.order_approved_at is not null
               and o.order_delivered_carrier_date is null
               then '2_审核后发货前取消'
           when o.order_delivered_carrier_date is not null
               then '3_发货后取消'
           else '4_其他'
           end                                            as cancel_stage,
       count(*)                                           as cancel_cnt,
       round(100.0 * count(*) / sum(count(*)) over (), 2) as pct
from olist_orders_dataset o
where o.order_status = 'canceled'
group by cancel_stage
order by cancel_stage;

-- =============================================
-- 5.1 取消阶段 × 支付方式
-- 目的：识别不同支付方式的取消主要发生在哪个阶段
-- =============================================

with cancel_stage as (select o.order_id,
                             case
                                 when o.order_approved_at is null
                                     then '1_未审核即取消'
                                 when o.order_approved_at is not null
                                     and o.order_delivered_carrier_date is null
                                     then '2_审核后发货前取消'
                                 when o.order_delivered_carrier_date is not null
                                     then '3_发货后取消'
                                 else '4_其他'
                                 end as cancel_stage
                      from olist_orders_dataset o
                      where o.order_status = 'canceled')
select c.cancel_stage,
       p.payment_type,
       count(*) as cancel_cnt,
       round(
               100.0 * count(*) / sum(count(*)) over (partition by c.cancel_stage),
               2
       )        as pct_in_stage
from cancel_stage c
         join olist_order_payments_dataset p
              on c.order_id = p.order_id
group by c.cancel_stage, p.payment_type
order by c.cancel_stage, cancel_cnt desc;

/*
结论：
1. 不同支付方式的取消发生阶段存在明显差异
2. 在“未审核即取消”阶段，voucher 占比最高（55.13%），明显高于 credit_card（33.97%）
3. 在“审核后发货前取消”阶段，credit_card 占绝对主导（75.81%）
4. 说明 voucher 更像下单后立刻反悔型风险，而 credit_card 由于订单体量更大，主导了审核后发货前的取消
5. 因此，平台取消风险并非单一模式，而是不同支付方式对应不同的取消阶段特征
*/

-- =============================================
-- 6. 时间窗口验证：取消集中在下单后首小时
-- =============================================

select case
           when timestampdiff(hour, order_purchase_timestamp, order_approved_at) < 1 then '1_1小时内'
           when timestampdiff(hour, order_purchase_timestamp, order_approved_at) < 24 then '2_1-24小时'
           when timestampdiff(hour, order_purchase_timestamp, order_approved_at) < 72 then '3_1-3天'
           else '4_3天以上'
           end  as cancel_window,
       count(*) as cancel_count
from olist_orders_dataset
where order_status = 'canceled'
  and order_approved_at is not null
  and order_purchase_timestamp is not null
group by cancel_window
order by cancel_window;

/*
结论：
1. 66% 的取消集中在下单后 1 小时内
2. 取消量随后快速下降
3. 这进一步证明取消本质是即时反悔，而不是履约过程中的体验恶化
*/

-- =============================================
-- 7. 用户稳定性验证：首购 vs 复购
-- =============================================

    with user_order_rank as (select o.order_id,
                                    o.customer_id,
                                    c.customer_unique_id,
                                    o.order_status,
                                    o.order_purchase_timestamp,
                                    row_number() over (
                                        partition by c.customer_unique_id
                                        order by o.order_purchase_timestamp
                                        ) as order_rank
                             from olist_orders_dataset o
                                      join olist_customers_dataset c
                                           on o.customer_id = c.customer_id)
    select case
               when order_rank = 1 then '1_首购用户'
               else '2_复购用户'
               end                                                    as user_type,
           count(*)                                                   as total_orders,
           sum(case when order_status = 'canceled' then 1 else 0 end) as canceled_orders,
           round(
                   100.0 * sum(case when order_status = 'canceled' then 1 else 0 end) / count(*),
                   2
           )                                                          as cancel_rate_pct
    from user_order_rank
    group by user_type
    order by user_type;

/*
结论：
1. 首购用户取消率 0.59%
2. 复购用户取消率 1.82%，约为首购用户的 3 倍
3. 取消风险并不只来自新客犹豫，老客同样存在明显反悔行为
4. 但复购订单样本量较小，结论应保守表述
5. 复购用户更熟悉 voucher 的使用，可能存在"囤券下单、冷静取消"的行为模式，建议对复购用户的 voucher 订单增加确认环节
*/

-- =============================================
-- 7.1 首购 / 复购 × 支付方式
-- 目的：解释复购用户取消率更高是否与支付方式结构有关
-- =============================================
with user_order_rank as (select o.order_id,
                                c.customer_unique_id,
                                o.order_status,
                                o.order_purchase_timestamp,
                                row_number() over (
                                    partition by c.customer_unique_id
                                    order by o.order_purchase_timestamp
                                    ) as order_rank
                         from olist_orders_dataset o
                                  join olist_customers_dataset c
                                       on o.customer_id = c.customer_id),
     order_user_tag as (select order_id,
                               order_status,
                               case
                                   when order_rank = 1 then '1_首购用户'
                                   else '2_复购用户'
                                   end as user_type
                        from user_order_rank)
select u.user_type,
       p.payment_type,
       count(*)                                                     as total_orders,
       sum(case when u.order_status = 'canceled' then 1 else 0 end) as canceled_orders,
       round(
               100.0 * sum(case when u.order_status = 'canceled' then 1 else 0 end) / count(*),
               2
       )                                                            as cancel_rate_pct
from order_user_tag u
         join olist_order_payments_dataset p
              on u.order_id = p.order_id
group by u.user_type, p.payment_type
having count(*) >= 30
order by u.user_type, p.payment_type;

/*
结论：
1. 首购与复购用户在不同支付方式下的取消率差异明显
2. 首购用户中，voucher 取消率为 1.38%，已高于 credit_card（0.57%）和 boleto（0.48%）
3. 复购用户中，voucher 取消率高达 11.90%，远高于 credit_card（0.70%）与 boleto（0.34%）
4. 说明复购用户取消率更高，并不是所有支付方式共同抬升，而是主要由 voucher 支付方式拉动
5. 这进一步支持“高风险不只来自高价订单本身，更集中在特定支付方式组合”这一判断
*/

-- =============================================
-- 8. 稳定性验证：分期不是风险来源
-- =============================================

select case
           when p.payment_installments = 1 then '1_单期'
           when p.payment_installments between 2 and 5 then '2_低分期2-5期'
           when p.payment_installments between 6 and 10 then '3_中分期6-10期'
           else '4_高分期10期以上'
           end                                                      as installment_group,
       count(*)                                                     as total_orders,
       sum(case when o.order_status = 'canceled' then 1 else 0 end) as canceled_orders,
       round(
               100.0 * sum(case when o.order_status = 'canceled' then 1 else 0 end) / count(*),
               2
       )                                                            as cancel_rate_pct
from olist_orders_dataset o
         join olist_order_payments_dataset p
              on o.order_id = p.order_id
where p.payment_type = 'credit_card'
group by installment_group
order by installment_group;

/*
结论：
1. 单期取消率 0.56%，高分期取消率 0.58%
2. 分期数增加并未显著提高取消率
3. 高分期虽然对应更高客单价，但用户决策更稳定
4. 分期不是风险放大器，反而可能在一定程度上缓冲高价压力
*/

-- =============================================
-- 9. 平台侧失败补充：unavailable 分析
-- 目的：区分用户主动取消与平台侧库存失败
-- =============================================

select order_status,
       count(*) as order_cnt,
       round(
               100.0 * count(*) / sum(count(*)) over (),
               2
       )        as pct
from olist_orders_dataset
where order_status in ('canceled', 'unavailable')
group by order_status;

select c.customer_state,
       count(*) as unavailable_orders
from olist_orders_dataset o
         join olist_customers_dataset c
              on o.customer_id = c.customer_id
where o.order_status = 'unavailable'
group by c.customer_state
order by unavailable_orders desc;

select round(avg(cast(p.payment_value as float)), 2) as avg_unavailable_value
from olist_orders_dataset o
         join olist_order_payments_dataset p
              on o.order_id = p.order_id
where o.order_status = 'unavailable';

/*
结论：
1. 在终态失败订单中，unavailable 609 单，占 49.35%；canceled 625 单，占 50.65%
2. 说明平台侧失败与用户主动取消规模几乎相当，unavailable 不能被简单视为边缘问题
3. unavailable 平均订单金额为 194.88，高于 canceled 的 157.71，说明平台侧失败对应的单笔损失更大
4. unavailable 订单主要集中在 sp、mg、rj 等核心交易州，更接近供给 / 库存稳定性问题
5. 因此，canceled 与 unavailable 应分为两条失败主线分别管理：前者属于用户决策风险，后者属于平台供给风险
*/

-- =============================================
-- 10. 损失量化：取消风险到底值多少钱
-- 目的：将风险识别转化为可量化的业务影响
-- =============================================

-- 10.1 各支付方式取消订单的总金额损失
with cancel_loss as (select p.payment_type,
                            count(distinct o.order_id)     as cancel_order_cnt,
                            round(sum(p.payment_value), 2) as total_loss
                     from olist_orders_dataset o
                              join olist_order_payments_dataset p
                                   on o.order_id = p.order_id
                     where o.order_status = 'canceled'
                     group by p.payment_type),
     platform_gmv as (select round(sum(p.payment_value), 2) as gmv
                      from olist_orders_dataset o
                               join olist_order_payments_dataset p
                                    on o.order_id = p.order_id
                      where o.order_status = 'delivered')
select cl.payment_type                               as '支付方式',
       cl.cancel_order_cnt                           as '取消订单数',
       cl.total_loss                                 as '取消总金额',
       round(cl.total_loss / g.gmv * 100, 4)         as '占平台GMV比例(%)',
       round(cl.total_loss / cl.cancel_order_cnt, 2) as '取消均价'
from cancel_loss cl
         cross join platform_gmv g
order by cl.total_loss desc;

/*
结论：
1. 信用卡取消总金额 97,375 元，占平台 GMV 的 0.63%，取消均价 219
2. Voucher 取消总金额 25,665 元，占平台 GMV 的 0.17%，取消均价 273
3. Voucher 单笔取消损失高于信用卡（273 vs 219），但绝对损失规模由信用卡主导
4. 全支付方式取消损失合计约 14.3 万元，占平台 GMV 不足 1%
5. 虽然整体损失比例不高，但 Voucher 的取消率远超其他支付方式，
   且高价区间尤为突出，属于"损失集中、可干预"的风险点
*/


-- ============================================================
-- 口径1：纯单一支付方式
-- ============================================================
with pure_payment as (
    select order_id,
           max(payment_type)        as payment_type,
           sum(payment_value)       as order_payment_value
    from olist_order_payments_dataset
    group by order_id
    having count(distinct payment_type) = 1
)
select payment_type                                                    as '支付方式',
       count(*)                                                        as '总订单数',
       sum(case when o.order_status = 'canceled' then 1 else 0 end)   as '取消订单数',
       round(100.0 * sum(case when o.order_status = 'canceled' then 1 else 0 end)
                 / count(*), 2)                                        as '取消率(%)'
from pure_payment p
         join olist_orders_dataset o on p.order_id = o.order_id
where p.order_payment_value >= 300
  and p.payment_type in ('credit_card', 'voucher')
group by payment_type;

/*

支付方式        总订单数    取消订单数   取消率(%)
credit_card,    8268,     65,         0.79
voucher,        75,       15,         20.00

*/

-- ============================================================
-- 口径2：按主支付方式（金额占比最大）
-- ============================================================
with payment_with_total as (
    select order_id,
           payment_type,
           payment_value,
           sum(payment_value) over (partition by order_id) as order_payment_value,
           row_number() over (
               partition by order_id
               order by payment_value desc
               )                                               as rn
    from olist_order_payments_dataset
),
     dominant_payment as (
         select order_id,
                payment_type as dominant_type,
                order_payment_value
         from payment_with_total
         where rn = 1
     )
select dominant_type                                                   as '支付方式',
       count(*)                                                        as '总订单数',
       sum(case when o.order_status = 'canceled' then 1 else 0 end)   as '取消订单数',
       round(100.0 * sum(case when o.order_status = 'canceled' then 1 else 0 end)
                 / count(*), 2)                                        as '取消率(%)'
from dominant_payment d
         join olist_orders_dataset o on d.order_id = o.order_id
where d.order_payment_value >= 300
  and d.dominant_type in ('credit_card', 'voucher')
group by dominant_type;

/*

支付方式        总订单数    取消订单数   取消率(%)
credit_card,    8378,     67,         0.80
voucher,        167,       16,        9.58
*/

-- ============================================================
-- 附：摸底混合支付占比（顺手确认污染程度）
-- ============================================================
with payment_category as (
    select order_id,
           count(distinct payment_type)  as type_count,
           sum(payment_value)            as order_payment_value,
           max(case when payment_type = 'voucher' then 1 else 0 end) as has_voucher,
           max(case when payment_type = 'credit_card' then 1 else 0 end) as has_credit
    from olist_order_payments_dataset
    group by order_id
)
select case
           when type_count = 1 and has_voucher = 1  then 'pure_voucher'
           when type_count = 1 and has_credit = 1   then 'pure_credit_card'
           when type_count > 1 and has_voucher = 1  then 'mixed_with_voucher'
           when type_count > 1 and has_credit = 1   then 'mixed_with_credit'
           else 'other'
           end                                           as '分类',
       count(*)                                      as '订单数',
       sum(case when order_payment_value >= 300 then 1 else 0 end) as '其中300+订单数'
from payment_category
group by 1
order by 2 desc;

-- 10.3 干预价值估算：Voucher 取消率降到信用卡同水平能挽回多少
with order_payment as (select o.order_id,
                              o.order_status,
                              p.payment_type,
                              sum(p.payment_value) as order_payment_value
                       from olist_orders_dataset o
                                join olist_order_payments_dataset p
                                     on o.order_id = p.order_id
                       group by o.order_id, o.order_status, p.payment_type),
     voucher_stats as (select count(*)                                                   as total_orders,
                              sum(case when order_status = 'canceled' then 1 else 0 end) as cancel_cnt,
                              round(100.0 * sum(case when order_status = 'canceled' then 1 else 0 end)
                                        / count(*), 2)                                   as cancel_rate,
                              round(avg(case
                                            when order_status = 'canceled'
                                                then order_payment_value end), 2)        as cancel_avg
                       from order_payment
                       where payment_type = 'voucher'),
     credit_card_rate as (select round(100.0 * sum(case when order_status = 'canceled' then 1 else 0 end)
                                           / count(*), 2) as cancel_rate
                          from order_payment
                          where payment_type = 'credit_card')
select v.total_orders                                             as 'Voucher总订单数',
       v.cancel_cnt                                               as '当前取消数',
       v.cancel_rate                                              as '当前取消率(%)',
       c.cancel_rate                                              as '信用卡取消率(%)',
       round(v.total_orders * c.cancel_rate / 100)                as '目标取消数',
       v.cancel_cnt - round(v.total_orders * c.cancel_rate / 100) as '可减少取消数',
       round(
               (v.cancel_cnt - round(v.total_orders * c.cancel_rate / 100))
                   * v.cancel_avg, 2
       )                                                          as '预计可挽回金额'
from voucher_stats v
         cross join credit_card_rate c;

/*
结论：
1. Voucher 当前取消率 2.43%，信用卡取消率 0.58%
2. 如果通过干预将 Voucher 取消率降至信用卡同水平，
   预计可减少 72 单取消，挽回约 19,658 元
3. 这个数字本身占平台 GMV 比例不大（约 0.13%），
   但代表的是"已识别、可干预、有明确特征"的损失，
   干预成本低而确定性高，适合作为优先治理对象
4. 更重要的是，这套量化方法本身可以复用到其他风险组合的评估中
*/
